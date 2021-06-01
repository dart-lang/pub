// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'dart:io';

import 'package:http/http.dart' as http;

import '../http.dart';
import '../system_cache.dart';
import 'scheme.dart';

/// This client authenticates requests by injecting `Authentication` header to
/// requests.
///
/// Requests to URLs not under [serverBaseUrl] will not be authenticated.
class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._inner, this.scheme);

  final http.BaseClient _inner;

  /// Authentication scheme that could be used for authenticating requests.
  final AuthenticationScheme scheme;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    //
    // This check ensures that this client will only authenticate requests sent
    // to given serverBaseUrl. Otherwise credential leaks might ocurr when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    if (scheme.canAuthenticate(request.url.toString())) {
      request.headers[HttpHeaders.authorizationHeader] =
          await scheme.credential.getAuthorizationHeaderValue();
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Invoke [fn] with a [http.Client] capable of authenticating against
/// [serverBaseUrl].
///
/// Importantly, requests to URLs not under [serverBaseUrl] will not be
/// authenticated.
Future<T> withAuthenticatedClient<T>(
  SystemCache systemCache,
  String serverBaseUrl,
  Future<T> Function(http.Client) fn,
) async {
  final scheme = systemCache.credentialStore.findScheme(serverBaseUrl);
  final http.Client client =
      scheme == null ? httpClient : _AuthenticatedClient(httpClient, scheme);

  try {
    return await fn(client);
  } catch (error) {
    if (error is PubHttpException) {
      if (error.response.statusCode == 401) {
        // TODO(themisir): authentication is required for the server or
        // credential might be invalid.
      }
    }
    rethrow;
  }
}
