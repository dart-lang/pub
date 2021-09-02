// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:io';

import 'package:http/http.dart' as http;

import '../http.dart';
import '../log.dart' as log;
import '../system_cache.dart';
import 'token.dart';

/// This client authenticates requests by injecting `Authentication` header to
/// requests.
///
/// Requests to URLs not under [serverBaseUrl] will not be authenticated.
class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._inner, this.token);

  final http.BaseClient _inner;

  /// Authentication scheme that could be used for authenticating requests.
  final Token token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    //
    // This check ensures that this client will only authenticate requests sent
    // to given serverBaseUrl. Otherwise credential leaks might ocurr when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    if (token.canAuthenticate(request.url.toString())) {
      request.headers[HttpHeaders.authorizationHeader] =
          await token.getAuthorizationHeaderValue();
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
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
  final token = systemCache.tokenStore.findToken(hostedUrl);
  final http.Client client =
      token == null ? httpClient : _AuthenticatedClient(httpClient, token);

  try {
    return await fn(client);
  } on PubHttpException catch (error) {
    if (error.response?.statusCode == 401 ||
        error.response?.statusCode == 403) {
      // TODO(themisir): Do we need to match error.response.request.url with
      // the hostedUrl? Or at least we might need to log request.url to give
      // user additional insights on what's happening.

      String? serverMessage;

      try {
        final wwwAuthenticateHeaderValue =
            error.response.headers[HttpHeaders.wwwAuthenticateHeader];
        if (wwwAuthenticateHeaderValue != null) {
          final parsedValue = HeaderValue.parse(wwwAuthenticateHeaderValue,
              parameterSeparator: ',');
          if (parsedValue.parameters['realm'] == 'pub') {
            serverMessage = parsedValue.parameters['message'];
          }
        }
      } catch (_) {
        // Ignore errors might be caused when parsing invalid header values
      }

      if (error.response.statusCode == 401) {
        systemCache.tokenStore.removeMatchingTokens(hostedUrl);

        log.error(
          'Authentication requested by hosted server at: $hostedUrl\n'
          'You can use the following command to add token for the server:\n'
          '\n    pub token add $hostedUrl\n',
        );
      }
      if (error.response.statusCode == 403) {
        log.error(
          'Insufficient permissions to the resource in hosted server at: '
          '$hostedUrl\n'
          'You can use the following command to update token for the server:\n'
          '\n    pub token add $hostedUrl\n',
        );
      }

      if (serverMessage?.isNotEmpty == true) {
        // TODO(themisir): Sanitize and truncate serverMessage when needed.
        log.error(serverMessage);
      }
    }
    rethrow;
  }
}
