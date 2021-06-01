// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'credential.dart';

/// Bearer credential type that simply puts authorization header formatted as
/// `Bearer $token` to request.header.
@sealed
class BearerCredential extends Credential {
  BearerCredential(this.token);

  static const String kind = 'Bearer';

  /// Deserializes [map] into [BearerCredential].
  static BearerCredential fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) {
      throw FormatException(
          'Token kind is not compatible with BearerCredential.');
    }
    if (json['token'] is! String) {
      throw FormatException('Failed to parse bearer token from json.');
    }
    return BearerCredential(json['token'] as String);
  }

  /// Bearer token
  final String token;

  @override
  Map<String, Object> toJson() =>
      <String, Object>{'kind': kind, 'token': token};

  @override
  Future<String> getAuthorizationHeaderValue() => Future.value('Bearer $token');
}
