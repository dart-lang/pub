// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'credential.dart';

/// Bearer credential type that simply puts authorization header formatted as
/// `Bearer $token` to request.header.
class BearerCredential extends Credential {
  BearerCredential(this.token);

  static const String kind = 'Bearer';

  /// Deserializes [map] into [BearerCredential].
  static BearerCredential fromJson(Map<String, dynamic> map) =>
      BearerCredential(map['token'] as String);

  /// Bearer token
  final String token;

  @override
  Map<String, dynamic> toJson() =>
      <String, dynamic>{'kind': kind, 'token': token};

  @override
  Future<String> getAuthorizationHeaderValue() => Future.value('Bearer $token');
}
