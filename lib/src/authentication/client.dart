// ignore_for_file: import_of_legacy_library_into_null_safe

import 'package:http/http.dart' as http;

import '../http.dart';
import '../system_cache.dart';
import 'credential.dart';
import 'credential_store.dart';

/// This client automatically modifies request to contain required credentials
/// in request. For example some credentials might add `Authentication` header
/// to request.
class _AuthenticationClient extends http.BaseClient {
  _AuthenticationClient(
    this._inner, {
    required this.credential,
    required this.serverKey,
  });

  final http.BaseClient _inner;
  final Credential credential;
  final String serverKey;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Let's last time make sure that, we're allowed to use credential for this
    // request.
    if (serverKeyMatches(serverKey, request.url.toString())) {
      await credential.beforeRequest(request);
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

Future<T> withAuthenticatedClient<T>(
  SystemCache systemCache,
  String server,
  Future<T> Function(http.Client) fn, {
  List<String>? alsoMatches,
}) {
  final store = CredentialStore(systemCache);
  final match = store.getCredential(server, alsoMatches: alsoMatches);
  final http.Client client = match == null
      ? httpClient
      : _AuthenticationClient(
          httpClient,
          credential: match.last,
          serverKey: match.first,
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
