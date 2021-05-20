import 'package:http/http.dart' as http;
import 'credential_store.dart';

class AuthenticationClient extends http.BaseClient {
  AuthenticationClient(this._inner, {required this.credentialStore});

  final http.BaseClient _inner;
  final CredentialStore credentialStore;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var creds = credentialStore.getCredential(request.url.toString());
    if (creds != null) {
      await creds.beforeRequest(request);
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
