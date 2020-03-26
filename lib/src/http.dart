// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helpers for dealing with HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http_retry/http_retry.dart';
import 'package:http_throttle/http_throttle.dart';
import 'package:stack_trace/stack_trace.dart';

import 'command_runner.dart';
import 'io.dart';
import 'log.dart' as log;
import 'oauth2.dart' as oauth2;
import 'package.dart';
import 'sdk.dart';
import 'utils.dart';

/// Headers and field names that should be censored in the log output.
const _censoredFields = ['refresh_token', 'authorization'];

/// Headers required for pub.dartlang.org API requests.
///
/// The Accept header tells pub.dartlang.org which version of the API we're
/// expecting, so it can either serve that version or give us a 406 error if
/// it's not supported.
const pubApiHeaders = {'Accept': 'application/vnd.pub.v2+json'};

/// A unique ID to identify this particular invocation of pub.
final _sessionId = createUuid();

/// An HTTP client that transforms 40* errors and socket exceptions into more
/// user-friendly error messages.
class _PubHttpClient extends http.BaseClient {
  final _requestStopwatches = <http.BaseRequest, Stopwatch>{};

  http.Client _inner;

  _PubHttpClient([http.Client inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_shouldAddMetadata(request)) {
      request.headers['X-Pub-OS'] = Platform.operatingSystem;
      request.headers['X-Pub-Command'] = PubCommandRunner.command;
      request.headers['X-Pub-Session-ID'] = _sessionId;

      var environment = Platform.environment['PUB_ENVIRONMENT'];
      if (environment != null) {
        request.headers['X-Pub-Environment'] = environment;
      }

      var type = Zone.current[#_dependencyType];
      if (type != null) request.headers['X-Pub-Reason'] = type.toString();
    }

    _requestStopwatches[request] = Stopwatch()..start();
    request.headers[HttpHeaders.userAgentHeader] = 'Dart pub ${sdk.version}';
    _logRequest(request);

    final streamedResponse = await _inner.send(request);

    _logResponse(streamedResponse);

    return streamedResponse;
  }

  /// Whether extra metadata headers should be added to [request].
  bool _shouldAddMetadata(http.BaseRequest request) {
    if (runningFromTest && Platform.environment.containsKey('PUB_HOSTED_URL')) {
      if (request.url.origin != Platform.environment['PUB_HOSTED_URL']) {
        return false;
      }
    } else {
      if (request.url.origin != 'https://pub.dartlang.org') return false;
    }

    return true;
  }

  /// Logs the fact that [request] was sent, and information about it.
  void _logRequest(http.BaseRequest request) {
    var requestLog = StringBuffer();
    requestLog.writeln('HTTP ${request.method} ${request.url}');
    request.headers
        .forEach((name, value) => requestLog.writeln(_logField(name, value)));

    if (request.method == 'POST') {
      var contentTypeString = request.headers[HttpHeaders.contentTypeHeader];
      var contentType = ContentType.parse(contentTypeString ?? '');
      if (request is http.MultipartRequest) {
        requestLog.writeln();
        requestLog.writeln('Body fields:');
        request.fields.forEach(
            (name, value) => requestLog.writeln(_logField(name, value)));

        // TODO(nweiz): make MultipartRequest.files readable, and log them?
      } else if (request is http.Request) {
        if (contentType.value == 'application/x-www-form-urlencoded') {
          requestLog.writeln();
          requestLog.writeln('Body fields:');
          request.bodyFields.forEach(
              (name, value) => requestLog.writeln(_logField(name, value)));
        } else if (contentType.value == 'text/plain' ||
            contentType.value == 'application/json') {
          requestLog.write(request.body);
        }
      }
    }

    log.io(requestLog.toString().trim());
  }

  /// Logs the fact that [response] was received, and information about it.
  void _logResponse(http.StreamedResponse response) {
    // TODO(nweiz): Fork the response stream and log the response body. Be
    // careful not to log OAuth2 private data, though.

    var responseLog = StringBuffer();
    var request = response.request;
    var stopwatch = _requestStopwatches.remove(request)..stop();
    responseLog.writeln('HTTP response ${response.statusCode} '
        '${response.reasonPhrase} for ${request.method} ${request.url}');
    responseLog.writeln('took ${stopwatch.elapsed}');
    response.headers
        .forEach((name, value) => responseLog.writeln(_logField(name, value)));

    log.io(responseLog.toString().trim());
  }

  /// Returns a log-formatted string for the HTTP field or header with the given
  /// [name] and [value].
  String _logField(String name, String value) {
    if (_censoredFields.contains(name.toLowerCase())) {
      return '$name: <censored>';
    } else {
      return '$name: $value';
    }
  }
}

/// The [_PubHttpClient] wrapped by [httpClient].
final _pubClient = _PubHttpClient();

/// A set of all hostnames for which we've printed a message indicating that
/// we're waiting for them to come back up.
final _retriedHosts = <String>{};

/// Intercepts all requests and throws exceptions if the response was not
/// considered successful.
class _ThrowingClient extends http.BaseClient {
  final http.Client _inner;

  _ThrowingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _inner.send(request);
    } on SocketException catch (error, stackTraceOrNull) {
      // Work around issue 23008.
      var stackTrace = stackTraceOrNull ?? Chain.current();

      if (error.osError == null) rethrow;

      // Handle error codes known to be related to DNS or SSL issues. While it
      // is tempting to handle these error codes before retrying, saving time
      // for the end-user, it is known that DNS lookups can fail intermittently
      // in some cloud environments. Furthermore, since these error codes are
      // platform-specific (undocumented) and essentially cargo-culted along
      // skipping retries may lead to intermittent issues that could be fixed
      // with a retry. Failing to retry intermittent issues is likely to cause
      // customers to wrap pub in a retry loop which will not improve the
      // end-user experience.
      if (error.osError.errorCode == 8 ||
          error.osError.errorCode == -2 ||
          error.osError.errorCode == -5 ||
          error.osError.errorCode == 11001 ||
          error.osError.errorCode == 11004) {
        fail('Could not resolve URL "${request.url.origin}".', error,
            stackTrace);
      } else if (error.osError.errorCode == -12276) {
        fail(
            'Unable to validate SSL certificate for '
            '"${request.url.origin}".',
            error,
            stackTrace);
      } else {
        rethrow;
      }
    }

    var status = streamedResponse.statusCode;
    // 401 responses should be handled by the OAuth2 client. It's very
    // unlikely that they'll be returned by non-OAuth2 requests. We also want
    // to pass along 400 responses from the token endpoint.
    var tokenRequest = streamedResponse.request.url == oauth2.tokenEndpoint;
    if (status < 400 || status == 401 || (status == 400 && tokenRequest)) {
      return streamedResponse;
    }

    if (status == 406 && request.headers['Accept'] == pubApiHeaders['Accept']) {
      fail('Pub ${sdk.version} is incompatible with the current version of '
          '${request.url.host}.\n'
          'Upgrade pub to the latest version and try again.');
    }

    if (status == 500 &&
        (request.url.host == 'pub.dartlang.org' ||
            request.url.host == 'storage.googleapis.com')) {
      fail('HTTP error 500: Internal Server Error at ${request.url}.\n'
          'This is likely a transient error. Please try again later.');
    }

    throw PubHttpException(await http.Response.fromStream(streamedResponse));
  }
}

/// The HTTP client to use for all HTTP requests.
final httpClient = ThrottleClient(
    16,
    _ThrowingClient(RetryClient(_pubClient,
        retries: math.max(
          1, // Having less than 1 retry is **always** wrong.
          int.tryParse(Platform.environment['PUB_MAX_HTTP_RETRIES'] ?? '') ?? 7,
        ),
        when: (response) =>
            const [500, 502, 503, 504].contains(response.statusCode),
        whenError: (error, stackTrace) {
          if (error is! IOException) return false;

          var chain = Chain.forTrace(stackTrace);
          log.io('HTTP error:\n$error\n\n${chain.terse}');
          return true;
        },
        delay: (retryCount) {
          if (retryCount < 3) {
            // Retry quickly a couple times in case of a short transient error.
            //
            // Add a random delay to avoid retrying a bunch of parallel requests
            // all at the same time.
            return Duration(milliseconds: 500) * math.pow(1.5, retryCount) +
                Duration(milliseconds: random.nextInt(500));
          } else {
            // If the error persists, wait a long time. This works around issues
            // where an AppEngine instance will go down and need to be rebooted,
            // which takes about a minute.
            return Duration(seconds: 30);
          }
        },
        onRetry: (request, response, retryCount) {
          log.io('Retry #${retryCount + 1} for '
              '${request.method} ${request.url}...');
          if (retryCount != 3) return;
          if (!_retriedHosts.add(request.url.host)) return;
          log.message(
              'It looks like ${request.url.host} is having some trouble.\n'
              'Pub will wait for a while before trying to connect again.');
        })));

/// The underlying HTTP client wrapped by [httpClient].
http.Client get innerHttpClient => _pubClient._inner;
set innerHttpClient(http.Client client) => _pubClient._inner = client;

/// Runs [callback] in a zone where all HTTP requests sent to `pub.dartlang.org`
/// will indicate the [type] of the relationship between the root package and
/// the package being requested.
///
/// If [type] is [DependencyType.none], no extra metadata is added.
Future<T> withDependencyType<T>(
    DependencyType type, Future<T> Function() callback) {
  if (type == DependencyType.none) return callback();
  return runZoned(callback, zoneValues: {#_dependencyType: type});
}

/// Handles a successful JSON-formatted response from pub.dartlang.org.
///
/// These responses are expected to be of the form `{"success": {"message":
/// "some message"}}`. If the format is correct, the message will be printed;
/// otherwise an error will be raised.
void handleJsonSuccess(http.Response response) {
  var parsed = parseJsonResponse(response);
  if (parsed['success'] is! Map ||
      !parsed['success'].containsKey('message') ||
      parsed['success']['message'] is! String) {
    invalidServerResponse(response);
  }
  log.message(log.green(parsed['success']['message']));
}

/// Handles an unsuccessful JSON-formatted response from pub.dartlang.org.
///
/// These responses are expected to be of the form `{"error": {"message": "some
/// message"}}`. If the format is correct, the message will be raised as an
/// error; otherwise an [invalidServerResponse] error will be raised.
void handleJsonError(http.Response response) {
  var errorMap = parseJsonResponse(response);
  if (errorMap['error'] is! Map ||
      !errorMap['error'].containsKey('message') ||
      errorMap['error']['message'] is! String) {
    invalidServerResponse(response);
  }
  fail(log.red(errorMap['error']['message']));
}

/// Parses a response body, assuming it's JSON-formatted.
///
/// Throws a user-friendly error if the response body is invalid JSON, or if
/// it's not a map.
Map parseJsonResponse(http.Response response) {
  Object value;
  try {
    value = jsonDecode(response.body);
  } on FormatException {
    invalidServerResponse(response);
  }
  if (value is! Map) invalidServerResponse(response);
  return value;
}

/// Throws an error describing an invalid response from the server.
void invalidServerResponse(http.Response response) =>
    fail(log.red('Invalid server response:\n${response.body}'));

/// Exception thrown when an HTTP operation fails.
class PubHttpException implements Exception {
  final http.Response response;

  const PubHttpException(this.response);

  @override
  String toString() => 'HTTP error ${response.statusCode}: '
      '${response.reasonPhrase}';
}
