// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: import_of_legacy_library_into_null_safe

import 'package:http/http.dart' as http;

import '../http.dart';
import '../system_cache.dart';
import 'credential.dart';
import 'credential_store.dart';

/// This client automatically modifies request to contain required credentials
/// in request. For example some credentials might add `Authentication` header
/// to request.
class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(
    this._inner, {
    required this.credential,
    required this.serverBaseUrl,
  });

  final http.BaseClient _inner;
  final Credential credential;
  final String serverBaseUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    //
    // This check ensures that this client will only authenticate requests sent
    // to given serverBaseUrl. Otherwise credential leaks might ocurr when
    // archive_url hosted on 3rd party server that should not receive
    // credentials of the first party.
    if (serverBaseUrlMatches(serverBaseUrl, request.url.toString())) {
      await credential.beforeRequest(request);
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

Future<T> withAuthenticatedClient<T>(
  SystemCache systemCache,
  String serverBaseUrl,
  Future<T> Function(http.Client) fn,
) {
  final store = CredentialStore(systemCache);
  final credential = store.getCredential(serverBaseUrl);
  final http.Client client = credential == null
      ? httpClient
      : _AuthenticatedClient(
          httpClient,
          serverBaseUrl: credential.first,
          credential: credential.last,
        );

  return fn(client).catchError((error) {
    if (error is PubHttpException) {
      if (error.response.statusCode == 401) {
        // TODO(themisir): authentication is required for the server or
        // credential might be invalid.
      }
    }
  });
}
