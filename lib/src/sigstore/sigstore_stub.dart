// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Stub classes for `package:sigstore` when compiling for platforms without
/// `dart:ffi`.
class SigstoreBundle {
  static SigstoreBundle fromJson(String json) =>
      throw UnsupportedError('Sigstore is not supported on this platform.');

  String toJson() =>
      throw UnsupportedError('Sigstore is not supported on this platform.');
}

class SigstoreClient {
  static SigstoreClient create() =>
      throw UnsupportedError('Sigstore is not supported on this platform.');

  SigstoreVerificationResult verify(
    List<int> artifactBytes,
    bool isDigest,
    SigstoreBundle bundle,
    SigstoreVerificationPolicy policy,
  ) => throw UnsupportedError('Sigstore is not supported on this platform.');

  String refreshTrustedRoot(String mirrorUrl, String cacheDir) =>
      throw UnsupportedError('Sigstore is not supported on this platform.');
}

class SigstoreVerificationPolicy {
  static SigstoreVerificationPolicy create(
    String expectedIdentity,
    String expectedIssuer,
    bool offline,
    bool isStaging,
    String trustedRootJson,
    String publicKeyPem,
  ) => throw UnsupportedError('Sigstore is not supported on this platform.');
}

class SigstoreVerificationResult {
  bool isValid() =>
      throw UnsupportedError('Sigstore is not supported on this platform.');

  String verifiedIdentity() =>
      throw UnsupportedError('Sigstore is not supported on this platform.');

  String verifiedIssuer() =>
      throw UnsupportedError('Sigstore is not supported on this platform.');
}
