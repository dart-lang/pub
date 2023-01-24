// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  /// [_credential] might be `null`. In that case `authorization` header will not
  /// be injected to requests.
  _AuthenticatedClient(this._inner, this._credential);

  final http.BaseClient _inner;

  /// Authentication scheme that could be used for authenticating requests.
  final Credential? _credential;

  /// Detected that [_credential] are invalid, happens when server responds 401.
  bool _detectInvalidCredentials = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    //
    // This check ensures that this client will only authenticate requests sent
    // to given serverBaseUrl. Otherwise credential leaks might ocurr when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    if (_credential != null &&
        _credential!.canAuthenticate(request.url.toString())) {
      request.headers[HttpHeaders.authorizationHeader] =
          await _credential!.getAuthorizationHeaderValue();
    }

    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      _detectInvalidCredentials = true;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      _throwAuthException(response);
    }
    return response;
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
        final challenge =
            AuthenticationChallenge.parseHeader(header).firstWhereOrNull(
          (challenge) =>
              challenge.scheme == 'bearer' &&
              challenge.parameters['realm'] == 'pub' &&
              challenge.parameters['message'] != null,
        );
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
      serverMessage = String.fromCharCodes(
        serverMessage.runes.map((r) => 32 <= r && r <= 127 ? r : 32).take(1024),
      );
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
  final client = _AuthenticatedClient(globalHttpClient, credential);

  try {
    return await fn(client);
  } finally {
    if (client._detectInvalidCredentials) {
      // try to remove the credential, if we detected that it is invalid!
      final removed = systemCache.tokenStore.removeCredential(hostedUrl);
      if (removed) {
        log.warning('Invalid token for $hostedUrl deleted.');
      }
    }
  }
}
