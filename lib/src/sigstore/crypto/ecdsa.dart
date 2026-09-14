// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'ec.dart';

/// Pure Dart ECDSA signature verification without external dependencies.
final class EcdsaVerifier {
  EcdsaVerifier._();

  /// Verifies an ECDSA signature [signature] against a precomputed message [hash]
  /// using the provided [publicKey].
  ///
  /// The [hash] is typically a SHA-256 or SHA-384 digest depending on the curve parameters
  /// of [publicKey].
  ///
  /// Returns `true` if and only if the signature is valid for the given hash and public key.
  ///
  /// It is an error if [hash] is empty.
  ///
  /// Performance is dominated by elliptic curve point multiplication: O(log n) group operations.
  static bool verify({
    required Uint8List hash,
    required EcSignature signature,
    required EcPublicKey publicKey,
  }) {
    return PureEcdsaVerifier.verify(
      digest: hash,
      signature: signature,
      publicKey: publicKey,
    );
  }
}
