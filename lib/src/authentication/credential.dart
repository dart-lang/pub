// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'bearer.dart';

typedef CredentialDeserializer = Credential Function(Map<String, dynamic>);

final Map<String, CredentialDeserializer> _credentialKinds = {
  BearerCredential.kind: BearerCredential.fromJson,
};

/// Credentials used to authenticate requests sent to auth - protected hosted
/// pub repositories. This class is base class for different credential type
/// implementations like [BearerCredential].
abstract class Credential {
  /// Parse Credential details from given [map]. If parsing fails this method
  /// will return null.
  static Credential fromJson(Map<String, dynamic> map) {
    final credentialKind = map['kind'] as String?;
    if (credentialKind?.isNotEmpty != true) {
      throw FormatException('Credential kind is not provided.');
    }

    if (_credentialKinds.containsKey(credentialKind)) {
      return _credentialKinds[credentialKind]!(map);
    } else {
      throw FormatException(
          'Credential kind "$credentialKind" is not supported.');
    }
  }

  /// Converts this instance into Json map.
  Map<String, Object> toJson();

  /// Returns future that resolves "Authorization" header value used for
  /// authenticating.
  Future<String> getAuthorizationHeaderValue();
}
