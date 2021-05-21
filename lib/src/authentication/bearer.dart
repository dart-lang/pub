// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:http/http.dart' as http;

import 'credential.dart';

/// Bearer credential type that simply puts authorization header formatted as
/// `Bearer $token` to request.header.
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
