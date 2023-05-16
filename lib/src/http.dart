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
import 'log.dart' as log;
import 'pubspec.dart';
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
    _requestStopwatches[request] = Stopwatch()..start();
    request.headers[HttpHeaders.userAgentHeader] = 'Dart pub ${sdk.version}';
    _logRequest(request);

    final streamedResponse = await _inner.send(request);

    _logResponse(streamedResponse);

    return streamedResponse;
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
          (name, value) => requestLog.writeln(_logField(name, value)),
        );

        // TODO(nweiz): make MultipartRequest.files readable, and log them?
      } else if (request is http.Request) {
        if (contentType.value == 'application/x-www-form-urlencoded') {
          requestLog.writeln();
          requestLog.writeln('Body fields:');
          request.bodyFields.forEach(
            (name, value) => requestLog.writeln(_logField(name, value)),
          );
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

/// The [_PubHttpClient] wrapped by [globalHttpClient].
final _pubClient = _PubHttpClient();

/// The HTTP client to use for all HTTP requests.
final globalHttpClient = _pubClient;

/// The underlying HTTP client wrapped by [globalHttpClient].
/// This enables the ability to use a mock client in tests.
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

extension AttachHeaders on http.Request {
  /// Adds headers required for pub.dev API requests.
  void attachPubApiHeaders() {
    headers.addAll(pubApiHeaders);
  }

  /// Adds request metadata headers about the Pub tool's environment and the
  /// currently running command if the request URL indicates the destination is
  /// a Hosted Pub Repository.
  void attachMetadataHeaders() {
    if (!HostedSource.shouldSendAdditionalMetadataFor(url)) {
      return;
    }

    headers['X-Pub-OS'] = Platform.operatingSystem;
    headers['X-Pub-Command'] = PubCommand.command;
    headers['X-Pub-Session-ID'] = _sessionId;

    var environment = Platform.environment['PUB_ENVIRONMENT'];
    if (environment != null) {
      headers['X-Pub-Environment'] = environment;
    }

    var type = Zone.current[#_dependencyType];
    if (type != null && type != DependencyType.none) {
      headers['X-Pub-Reason'] = type.toString();
    }
  }
}

/// Handles a successful JSON-formatted response from pub.dev.
///
/// These responses are expected to be of the form `{"success": {"message":
/// "some message"}}`. If the format is correct, the message will be printed;
/// otherwise an error will be raised.
void handleJsonSuccess(http.Response response) {
  var parsed = parseJsonResponse(response);
  if (parsed['success'] is! Map ||
      !(parsed['success'] as Map).containsKey('message') ||
      parsed['success']['message'] is! String) {
    invalidServerResponse(response);
  }
  log.message(log.green(parsed['success']['message'] as Object));
}

/// Handles an unsuccessful JSON-formatted response from pub.dev.
///
/// These responses are expected to be of the form `{"error": {"message": "some
/// message"}}`. If the format is correct, the message will be raised as an
/// error; otherwise an [invalidServerResponse] error will be raised.
void handleJsonError(http.BaseResponse response) {
  if (response is! http.Response) {
    // Not likely to be a common code path, but necessary.
    // See https://github.com/dart-lang/pub/pull/3590#discussion_r1012978108
    fail(log.red('Invalid server response'));
  }
  var errorMap = parseJsonResponse(response);
  if (errorMap['error'] is! Map ||
      !(errorMap['error'] as Map).containsKey('message') ||
      errorMap['error']['message'] is! String) {
    invalidServerResponse(response);
  }
  fail(log.red(errorMap['error']['message'] as Object));
}

/// Parses a response body, assuming it's JSON-formatted.
///
/// Throws a user-friendly error if the response body is invalid JSON, or if
/// it's not a map.
Map parseJsonResponse(http.Response response) {
  Object value;
  try {
    value = jsonDecode(response.body) as Object;
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

  @override
  String toString() {
    return 'PubHttpException: $message';
  }
}

/// Exception thrown when an HTTP response is not Ok.
class PubHttpResponseException extends PubHttpException {
  final http.BaseResponse response;

  PubHttpResponseException(
    this.response, {
    String message = '',
    bool isIntermittent = false,
  }) : super(message, isIntermittent: isIntermittent);

  @override
  String toString() {
    var temp = 'PubHttpResponseException: HTTP error ${response.statusCode} '
        '${response.reasonPhrase}';
    if (message != '') {
      temp += ': $message';
    }
    return temp;
  }
}

/// Whether [e] is one of a few HTTP-related exceptions that subclass
/// [IOException]. Can be used if your try-catch block contains various
/// operations in addition to HTTP calls and so a [IOException] instance check
/// would be too coarse.
bool isHttpIOException(Object e) {
  return e is HttpException ||
      e is TlsException ||
      e is SocketException ||
      e is WebSocketException;
}

/// Program-wide limiter for concurrent network requests.
final _httpPool = Pool(16);

/// Runs the provided function [fn] and returns the response.
///
/// If there is an HTTP-related exception, an intermittent HTTP error response,
/// or an async timeout, [fn] is run repeatedly until there is a successful
/// response or at most seven total attempts have been made. If all attempts
/// fail, the final exception is re-thrown.
///
/// Each attempt is run within a [Pool] configured with 16 maximum resources.
Future<T> retryForHttp<T>(String operation, FutureOr<T> Function() fn) async {
  return await retry(
    () async => await _httpPool.withResource(() async => await fn()),
    retryIf: (e) async =>
        (e is PubHttpException && e.isIntermittent) ||
        e is TimeoutException ||
        isHttpIOException(e),
    onRetry: (exception, attemptNumber) async =>
        log.io('Attempt #$attemptNumber for $operation'),
    maxAttempts: math.max(
      1, // Having less than 1 attempt doesn't make sense.
      int.tryParse(Platform.environment['PUB_MAX_HTTP_RETRIES'] ?? '') ?? 7,
    ),
  );
}

extension Throwing on http.BaseResponse {
  /// See https://api.flutter.dev/flutter/dart-io/HttpClientRequest/followRedirects.html
  static const _redirectStatusCodes = [
    HttpStatus.movedPermanently,
    HttpStatus.movedTemporarily,
    HttpStatus.seeOther,
    HttpStatus.temporaryRedirect,
    HttpStatus.permanentRedirect
  ];

  /// Throws [PubHttpResponseException], calls [fail], or does nothing depending
  /// on the status code.
  ///
  /// If the code is in the 200 range or if its a 300 range redirect code,
  /// nothing is done. If the code is 408, 429, or in the 500 range,
  /// [PubHttpResponseException] is thrown with "isIntermittent" set to `true`.
  /// Otherwise, [PubHttpResponseException] is thrown with "isIntermittent" set
  /// to `false`.
  void throwIfNotOk() {
    if (statusCode >= 200 && statusCode <= 299) {
      return;
    } else if (_redirectStatusCodes.contains(statusCode)) {
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
      throw PubHttpResponseException(this, isIntermittent: true);
    } else {
      // Throw for all other status codes.
      throw PubHttpResponseException(this);
    }
  }
}

extension RequestSending on http.Client {
  /// Sends an HTTP request, reads the whole response body, validates the
  /// response headers, and if validation is successful, and returns it.
  ///
  /// The send method on [http.Client], which returns a [http.StreamedResponse],
  /// is the only method that accepts a request object. This method can be used
  /// when you need to send a request object but want a regular response object.
  ///
  /// If false is passed for [throwIfNotOk], the response will not be validated.
  /// See [http.BaseResponse.throwIfNotOk] extension for validation details.
  Future<http.Response> fetch(
    http.BaseRequest request, {
    bool throwIfNotOk = true,
  }) async {
    final streamedResponse = await send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (throwIfNotOk) {
      response.throwIfNotOk();
    }
    return response;
  }

  /// Sends an HTTP request, validates the response headers, and if validation
  /// is successful, returns a [http.StreamedResponse].
  ///
  /// If false is passed for [throwIfNotOk], the response will not be validated.
  /// See [http.BaseResponse.throwIfNotOk] extension for validation details.
  Future<http.StreamedResponse> fetchAsStream(
    http.BaseRequest request, {
    bool throwIfNotOk = true,
  }) async {
    final streamedResponse = await send(request);
    if (throwIfNotOk) {
      streamedResponse.throwIfNotOk();
    }
    return streamedResponse;
  }
}
