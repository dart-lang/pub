// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../exceptions.dart';
import '../http.dart';
import '../log.dart' as log;
import '../system_cache.dart';
import 'credential.dart';

/// This client authenticates requests by injecting `Authentication` header to
/// requests.
///
/// Requests to URLs not under [serverBaseUrl] will not be authenticated.
class _AuthenticatedClient extends http.BaseClient {
  /// Constructs Http client wrapper that injects `authorization` header to
  /// requests and handles authentication errors.
  ///
  /// [credential] might be `null`. In that case `authorization` header will not
  /// be injected to requests.
  _AuthenticatedClient(this._inner, this.credential);

  final http.BaseClient _inner;

  /// Authentication scheme that could be used for authenticating requests.
  final Credential? credential;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    //
    // This check ensures that this client will only authenticate requests sent
    // to given serverBaseUrl. Otherwise credential leaks might ocurr when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    if (credential != null &&
        credential!.canAuthenticate(request.url.toString())) {
      request.headers[HttpHeaders.authorizationHeader] =
          await credential!.getAuthorizationHeaderValue();
    }

    try {
      final response = await _inner.send(request);
      if (response.statusCode == 401) {
        _throwAuthException(response);
      }
      return response;
    } on PubHttpException catch (e) {
      if (e.response.statusCode == 403) {
        _throwAuthException(e.response);
      }
      rethrow;
    }
  }

  /// Throws [AuthenticationException] that includes response status code and
  /// message parsed from WWW-Authenticate header usign
  /// [RFC 7235 section 4.1][RFC] specifications.
  ///
  /// [RFC]: https://datatracker.ietf.org/doc/html/rfc7235#section-4.1
  void _throwAuthException(http.BaseResponse response) {
    String? serverMessage;
    if (response.headers.containsKey(HttpHeaders.wwwAuthenticateHeader)) {
      try {
        final header = response.headers[HttpHeaders.wwwAuthenticateHeader]!;
        final challenge = AuthenticationChallenge.parseHeader(header)
            .firstWhereOrNull((challenge) =>
                challenge.scheme == 'bearer' &&
                challenge.parameters['realm'] == 'pub' &&
                challenge.parameters['message'] != null);
        if (challenge != null) {
          serverMessage = challenge.parameters['message'];
        }
      } on FormatException {
        // Ignore errors might be caused when parsing invalid header values
      }
    }
    if (serverMessage != null) {
      // Only allow printable ASCII, map anything else to whitespace, take
      // at-most 1024 characters.
      serverMessage = String.fromCharCodes(serverMessage.runes
          .map((r) => 32 <= r && r <= 127 ? r : 32)
          .take(1024));
    }
    throw AuthenticationException(response.statusCode, serverMessage);
  }

  @override
  void close() => _inner.close();
}

/// Token authenticated related exception.
class AuthenticationException implements Exception {
  const AuthenticationException(this.statusCode, this.serverMessage);

  final int statusCode;
  final String? serverMessage;

  @override
  String toString() {
    var message = 'Authentication error ($statusCode)';
    if (serverMessage != null) {
      message += ': $serverMessage';
    }
    return message;
  }
}

/// Invoke [fn] with a [http.Client] capable of authenticating against
/// [hostedUrl].
///
/// Importantly, requests to URLs not under [hostedUrl] will not be
/// authenticated.
Future<T> withAuthenticatedClient<T>(
  SystemCache systemCache,
  Uri hostedUrl,
  Future<T> Function(http.Client) fn,
) async {
  final credential = systemCache.tokenStore.findCredential(hostedUrl);
  final http.Client client = _AuthenticatedClient(httpClient, credential);

  try {
    return await fn(client);
  } on AuthenticationException catch (error) {
    var message = '';

    if (error.statusCode == 401) {
      if (systemCache.tokenStore.removeCredential(hostedUrl)) {
        log.warning('Invalid token for $hostedUrl deleted.');
      }
      message = '$hostedUrl package repository requested authentication! '
          'You can provide credential using:\n'
          '    pub token add $hostedUrl';
    }
    if (error.statusCode == 403) {
      message = 'Insufficient permissions to the resource in $hostedUrl '
          'package repository. You can modify credential using:\n'
          '    pub token add $hostedUrl';
    }

    if (error.serverMessage?.isNotEmpty == true) {
      message += '\n${error.serverMessage}';
    }

    throw DataException(message);
  }
}
