import 'dart:io';

import 'package:http/http.dart' as http;

import 'credential.dart';

class BearerCredential extends Credential {
  BearerCredential(this.token);

  static BearerCredential fromMap(Map<String, dynamic> map) =>
      BearerCredential(map['token'] as String);

  final String token;

  @override
  String get authenticationType => 'Bearer';

  @override
  Future<http.BaseClient> createClient([http.Client? inner]) {
    return Future.value(_Client(token: token, inner: inner));
  }

  @override
  Map<String, dynamic> toMapInternal() {
    return <String, dynamic>{'token': token};
  }
}

class _Client extends http.BaseClient {
  _Client({required this.token, http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;
  final String token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
