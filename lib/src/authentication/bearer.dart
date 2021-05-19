import 'dart:io';

import 'package:http/http.dart';

import 'credential.dart';

class BearerCredential extends Credential {
  BearerCredential(this.token);

  static BearerCredential fromMap(Map<String, dynamic> map) =>
      BearerCredential(map['token'] as String);

  final String token;

  @override
  String get authenticationType => 'Bearer';

  @override
  Future<BaseClient> createClient() {
    return Future.value(_Client(token));
  }

  @override
  Map<String, dynamic> toMapInternal() {
    return <String, dynamic>{'token': token};
  }
}

class _Client extends BaseClient {
  _Client(this._token);

  final Client _client = Client();
  final String _token;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $_token';
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
