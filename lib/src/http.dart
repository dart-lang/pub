// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helpers for dealing with HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'dart:math' as math;

import 'package:http/http.dart' as http;
// import 'package:http/retry.dart';
import 'package:pool/pool.dart';
// import 'package:stack_trace/stack_trace.dart';

import 'command.dart';
import 'io.dart';
import 'log.dart' as log;
import 'oauth2.dart' as oauth2;
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

/// A set of all hostnames for which we've printed a message indicating that
/// we're waiting for them to come back up.
final _retriedHosts = <String>{};

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
  final bool couldRetry;

  PubHttpException(this.message, {this.couldRetry = false});
}

/// Exception thrown when an HTTP response is not OK.
class PubHttpResponseException extends PubHttpException {
  final http.Response response;

  PubHttpResponseException(this.response,
      {String message = '', bool couldRetry = false})
      : super(message, couldRetry: couldRetry);

  @override
  String toString() {
    var temp = 'HTTP error ${response.statusCode}: ${response.reasonPhrase}';
    if (message != '') {
      temp += ': $message';
    }
    return temp;
  }
}

extension on OSError {
  get isDnsError {
    // See https://github.com/dart-lang/pub/pull/2254#pullrequestreview-314895700
    const indeterminateOSCodes = [8, -2, -5];
    const windowsCodes = [11001, 11004];

    return indeterminateOSCodes.contains(errorCode) ||
        windowsCodes.contains(errorCode);
  }

  get isSslError {
    // TODO: does dart/pub use nspr anymore?
    const nsprCodes = [-12276];

    return nsprCodes.contains(errorCode);
  }
}

extension on http.StreamedResponse {
  /// Creates a copy of this response with [newStream] as the stream.
  http.StreamedResponse replacingStream(Stream<List<int>> newStream) {
    return http.StreamedResponse(newStream, statusCode,
        contentLength: contentLength,
        request: request,
        headers: headers,
        isRedirect: isRedirect,
        persistentConnection: persistentConnection,
        reasonPhrase: reasonPhrase);
  }
}

/// Program-wide limiter for concurrent network requests.
final _httpPool = Pool(16);

extension HttpRetrying on http.Client {
  Future<T> sendWithRetries<T>(
      {required FutureOr<http.Request> Function() composeRequest,
      required Future<T> Function(http.StreamedResponse response) onResponse,
      int maxAttempts = 8,
      FutureOr<bool> Function(Exception, StackTrace)? retryIf,
      FutureOr<void> Function(Exception e, int retryCount, http.Request request,
              http.StreamedResponse? response)?
          onRetry}) async {
    late http.Request request;
    http.StreamedResponse? managedResponse;

    return await retry(() async {
      final resource = await _httpPool.request();
      request = await composeRequest();

      http.StreamedResponse directResponse;
      try {
        directResponse = await send(request);
        directResponse.throwIfNotOK();
      } catch (_) {
        resource.release();
        rethrow;
      }

      // [PoolResource] has no knowledge of streams, so we must manually release
      // the resource once the stream is canceled or done. We pipe the response
      // stream through a [StreamController], which enables us to set up lifecycle
      // hooks.
      var didStreamActivate = false;
      final responseController = StreamController<List<int>>(
        sync: true,
        onListen: () => didStreamActivate = true,
      );

      // TODO: does this need to be in a try block? this internally calls
      // [addStream], which theoretically(?) could throw if the stream has an
      // error.
      unawaited(directResponse.stream.pipe(responseController));
      unawaited(responseController.done.then((_) => resource.release()));
      managedResponse =
          directResponse.replacingStream(responseController.stream);

      try {
        return await onResponse(managedResponse!);
      } catch (_) {
        rethrow;
      } finally {
        if (!didStreamActivate) {
          // Release resource if the stream was never subscribed to.
          unawaited(responseController.stream.listen(null).cancel());
        }
      }
    }, mapException: (e, stackTrace) {
      if (e is SocketException) {
        final osError = e.osError;
        if (osError == null) {
          return PubHttpException('Socket operation failure', couldRetry: true);
        }

        // Handle error codes known to be related to DNS or SSL issues. While it
        // is tempting to handle these error codes before retrying, saving time
        // for the end-user, it is known that DNS lookups can fail intermittently
        // in some cloud environments. Furthermore, since these error codes are
        // platform-specific (undocumented) and essentially cargo-culted along
        // skipping retries may lead to intermittent issues that could be fixed
        // with a retry. Failing to retry intermittent issues is likely to cause
        // customers to wrap pub in a retry loop which will not improve the
        // end-user experience.

        // TODO: should these return PubConnectException('msg', couldRetry: false)?
        if (osError.isDnsError) {
          fail('Could not resolve URL "${request.url.origin}".');
        } else if (osError.isSslError) {
          fail(
              'Unable to validate SSL certificate for "${request.url.origin}".');
        }
      }

      return e;
    }, retryIf: (e, stackTrace) async {
      // TODO: think about IOException. RetryClient used to catch IOException
      // from _PubHttpClient.

      return (e is PubHttpException && e.couldRetry) ||
          e is HttpException ||
          e is TimeoutException ||
          e is FormatException ||
          (retryIf != null && await retryIf(e, stackTrace));
    }, onRetry: (exception, retryCount) async {
      if (onRetry != null) {
        await onRetry(exception, retryCount, request, managedResponse);
      } else {
        log.io('Retry #${retryCount + 1} for '
            '${request.method} ${request.url}...');
      }

      if (retryCount != 3) return;
      if (!_retriedHosts.add(request.url.host)) return;
      log.message('It looks like ${request.url.host} is having some trouble.\n'
          'Pub will wait for a while before trying to connect again.');
    }, maxAttempts: maxAttempts);
  }
}

extension on http.BaseResponse {
  void throwIfNotOK() {
    // Retry if the response indicates a server error.
    if ([500, 502, 503, 504].contains(statusCode)) {
      throw PubHttpResponseException(this as http.Response, couldRetry: true);
    }

    // 401 responses should be handled by the OAuth2 client. It's very
    // unlikely that they'll be returned by non-OAuth2 requests. We also want
    // to pass along 400 responses from the token endpoint.
    var tokenRequest = request!.url == oauth2.tokenEndpoint;
    if (statusCode < 400 ||
        statusCode == 401 ||
        (statusCode == 400 && tokenRequest)) {
      return;
    }

    if (statusCode == 406 &&
        request?.headers['Accept'] == pubApiHeaders['Accept']) {
      fail('Pub ${sdk.version} is incompatible with the current version of '
          '${request?.url.host}.\n'
          'Upgrade pub to the latest version and try again.');
    }

    if (statusCode == 500 &&
        (request!.url.host == 'pub.dartlang.org' ||
            request!.url.host == 'storage.googleapis.com')) {
      fail('HTTP error 500: Internal Server Error at ${request!.url}.\n'
          'This is likely a transient error. Please try again later.');
    }
  }
}
