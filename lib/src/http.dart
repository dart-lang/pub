// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helpers for dealing with HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';

import 'command.dart';
import 'io.dart';
import 'log.dart' as log;
import 'package.dart';
import 'sdk.dart';
import 'source/hosted.dart';
import 'utils.dart';

/// Headers and field names that should be censored in the log output.
const _censoredFields = ['refresh_token', 'authorization'];

/// Headers required for pub.dev API requests.
///
/// The Accept header tells pub.dev which version of the API we're
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

  _PubHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_shouldAddMetadata(request)) {
      request.headers['X-Pub-OS'] = Platform.operatingSystem;
      request.headers['X-Pub-Command'] = PubCommand.command;
      request.headers['X-Pub-Session-ID'] = _sessionId;

      var environment = Platform.environment['PUB_ENVIRONMENT'];
      if (environment != null) {
        request.headers['X-Pub-Environment'] = environment;
      }

      var type = Zone.current[#_dependencyType];
      if (type != null && type != DependencyType.none) {
        request.headers['X-Pub-Reason'] = type.toString();
      }
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
      if (!HostedSource.isPubDevUrl(request.url.toString())) return false;
    }

    if (Platform.environment.containsKey('CI') &&
        Platform.environment['CI'] != 'false') {
      return false;
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
    var request = response.request!;
    var stopwatch = _requestStopwatches.remove(request)!..stop();
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

  @override
  void close() => _inner.close();
}

/// The [_PubHttpClient] wrapped by [httpClient].
final _pubClient = _PubHttpClient();

/// The HTTP client to use for all HTTP requests.
final httpClient = _pubClient;

/// The underlying HTTP client wrapped by [httpClient].
http.Client get innerHttpClient => _pubClient._inner;
set innerHttpClient(http.Client client) => _pubClient._inner = client;

/// Runs [callback] in a zone where all HTTP requests sent to `pub.dev`
/// will indicate the [type] of the relationship between the root package and
/// the package being requested.
///
/// If [type] is [DependencyType.none], no extra metadata is added.
Future<T> withDependencyType<T>(
  DependencyType type,
  Future<T> Function() callback,
) {
  return runZoned(callback, zoneValues: {#_dependencyType: type});
}

/// Handles a successful JSON-formatted response from pub.dev.
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

/// Handles an unsuccessful JSON-formatted response from pub.dev.
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
Never invalidServerResponse(http.Response response) =>
    fail(log.red('Invalid server response:\n${response.body}'));

/// Exception thrown when an HTTP operation fails.
class PubHttpException implements Exception {
  final String message;
  final bool isIntermittent;

  PubHttpException(this.message, {this.isIntermittent = false});
}

/// Exception thrown when an HTTP response is not OK.
class PubHttpResponseException extends PubHttpException {
  final http.Response response;

  PubHttpResponseException(this.response,
      {String message = '', bool isIntermittent = false})
      : super(message, isIntermittent: isIntermittent);

  @override
  String toString() {
    var temp = 'HTTP error ${response.statusCode}: ${response.reasonPhrase}';
    if (message != '') {
      temp += ': $message';
    }
    return temp;
  }
}

/// Program-wide limiter for concurrent network requests.
final _httpPool = Pool(16);

Future<T> retryForHttp<T>(String operation, FutureOr<T> Function() fn) async {
  return await retry(
      () async => await _httpPool.withResource(() async => await fn()),
      retryIf: (e) async =>
          (e is PubHttpException && e.isIntermittent) ||
          e is TimeoutException ||
          e is HttpException ||
          e is TlsException ||
          e is SocketException ||
          e is WebSocketException,
      onRetry: (exception, retryCount) async =>
          log.io('Retry #${retryCount + 1} for $operation'),
      maxAttempts: math.max(
        1, // Having less than 1 attempt doesn't make sense.
        int.tryParse(Platform.environment['PUB_MAX_HTTP_RETRIES'] ?? '') ?? 7,
      ));
}

extension Throwing on http.BaseResponse {
  void throwIfNotOk() {
    if (statusCode >= 200 && statusCode <= 299) {
      return;
    } else if (statusCode == HttpStatus.notAcceptable &&
        request?.headers['Accept'] == pubApiHeaders['Accept']) {
      fail('Pub ${sdk.version} is incompatible with the current version of '
          '${request?.url.host}.\n'
          'Upgrade pub to the latest version and try again.');
    } else if (statusCode >= 500 ||
        statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests) {
      // Throw if the response indicates a server error or an intermittent
      // client error, but mark it as intermittent so it can be retried.
      throw PubHttpResponseException(this as http.Response,
          isIntermittent: true);
    } else {
      // Throw for all other status codes.
      throw PubHttpResponseException(this as http.Response);
    }
  }
}
