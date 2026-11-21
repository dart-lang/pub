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
import '../utils.dart';
import 'auth_helper.dart';
import 'credential.dart';

/// Information available to a credential helper during package resolution.
HelperContext readPackageContext(String package) => (
  package: package,
  version: null,
  archive: null,
  attestations: null,
);

/// This client authenticates requests by injecting `Authentication` header to
/// requests.
///
/// Requests to URLs not under [_credential]'s url will not be authenticated.
class _AuthenticatedClient extends http.BaseClient {
  /// Constructs Http client wrapper that injects `authorization` header to
  /// requests and handles authentication errors.
  ///
  /// [_credential] might be `null`. In that case `authorization` header will
  /// not be injected to requests.
  _AuthenticatedClient(this._inner, this._credential, this._createContext);

  final HelperContext Function() _createContext;
  late final HelperContext _context = _createContext();

  final http.Client _inner;

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
    // to given serverBaseUrl. Otherwise credential leaks might occur when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    final credential = _credential;
    final helper = credential?.helper;
    if (credential != null && helper != null) {
      var remaining = request.maxRedirects;
      final follow = request.followRedirects;
      while (_inScope(credential.url, request.url)) {
        request.followRedirects = false;
        request.headers.addAll(
          await helper.headers(
            credential.url,
            _context,
            request.method,
            request.url,
          ),
        );
        final response = await _inner.send(request);
        if (request.headers.containsKey('dpop')) {
          final nonce = response.headers['dpop-nonce'];
          if (nonce != null &&
              RegExp(r'^[\x21\x23-\x5b\x5d-\x7e]+$').hasMatch(nonce)) {
            if (response.statusCode == 401 && _requestsNonce(response)) {
              helper.resourceNonce = nonce;
              await response.stream.drain<void>();
              throw const _NonceChallenge();
            }
            if (response.statusCode >= 200 && response.statusCode < 300) {
              helper.resourceNonce = nonce;
            }
          }
        }
        if (response.statusCode == 401) helper.invalidate(_context);
        if (response.statusCode == 401 || response.statusCode == 403) {
          _throwAuthException(response);
        }
        final location = response.headers['location'];
        if (!follow ||
            request.method != 'GET' ||
            location == null ||
            ![301, 302, 303, 307, 308].contains(response.statusCode)) {
          return response;
        }
        await response.stream.drain<void>();
        if (remaining-- == 0) throw const HttpException('Too many redirects');
        final next = http.Request('GET', request.url.resolve(location));
        if (_inScope(credential.url, next.url)) {
          next.headers.addAll(request.headers);
          next.headers.remove('authorization');
          next.headers.remove('dpop');
        }
        request = next;
      }
      final response = await _inner.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        _throwAuthException(response);
      }
      return response;
    }
    if (_credential != null &&
        _credential.canAuthenticate(request.url.toString())) {
      request.headers[HttpHeaders.authorizationHeader] =
          await _credential.getAuthorizationHeaderValue();
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

  static bool _requestsNonce(http.BaseResponse response) {
    final header = response.headers['www-authenticate'];
    if (header == null) return false;
    try {
      return AuthenticationChallenge.parseHeader(header).any(
        (challenge) =>
            challenge.scheme == 'dpop' &&
            challenge.parameters['error'] == 'use_dpop_nonce',
      );
    } on FormatException {
      return false;
    }
  }

  static bool _inScope(Uri base, Uri target) {
    if (target.userInfo.isNotEmpty ||
        base.scheme != target.scheme ||
        base.host != target.host ||
        base.port != target.port) {
      return false;
    }
    final segments = target.normalizePath().pathSegments;
    if (segments.any(
      (s) => s == '.' || s == '..' || s.contains('/') || s.contains(r'\'),
    )) {
      return false;
    }
    final prefix = base.path;
    final path = target.normalizePath().path;
    return prefix.isEmpty ||
        path == prefix ||
        '$path/' == prefix ||
        path.startsWith(prefix);
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
        final challenge = AuthenticationChallenge.parseHeader(
          header,
        ).firstWhereOrNull(
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
      serverMessage = sanitizeForTerminal(serverMessage);
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

class _NonceChallenge extends AuthenticationException
    implements DPoPNonceRequired {
  const _NonceChallenge()
    : super(401, 'Repository requires a fresh DPoP proof.');
}

/// Invoke [fn] with a [http.Client] capable of authenticating against
/// [hostedUrl].
///
/// Importantly, requests to URLs not under [hostedUrl] will not be
/// authenticated.
Future<T> withAuthenticatedClient<T>(
  SystemCache systemCache,
  Uri hostedUrl,
  Future<T> Function(http.Client) fn, {
  required HelperContext Function() context,
}) async {
  final credential = systemCache.tokenStore.findCredential(hostedUrl);
  final client = _AuthenticatedClient(globalHttpClient, credential, context);

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
