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
  Future<void> beforeRequest(http.BaseRequest request) async {
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
  }

  @override
  Map<String, dynamic> toMapInternal() {
    return <String, dynamic>{'token': token};
  }
}
