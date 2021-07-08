// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'bearer.dart';

typedef CredentialDeserializer = Credential Function(Map<String, dynamic>);

/// Credentials used to authenticate requests sent to auth - protected hosted
/// pub repositories. This class is base class for different credential type
/// implementations like [BearerCredential].
abstract class Credential {
  /// Parse Credential details from given [map]. If parsing fails this method
  /// will return null.
  factory Credential.fromJson(Map<String, dynamic> map) {
    if (map['kind'] is! String) {
      throw FormatException('Credential kind is not provided.');
    }

    final kind = map['kind'] as String;
    switch (kind) {
      case BearerCredential.kind:
        return BearerCredential.fromJson(map);
      default:
        throw FormatException('Credential kind "$kind" is not supported.');
    }
  }

  /// Converts this instance into Json map.
  Map<String, Object> toJson();

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  Future<String> getAuthorizationHeaderValue();
}
