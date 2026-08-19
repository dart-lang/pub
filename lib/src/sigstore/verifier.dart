// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:sigstore/sigstore.dart'
    hide loadTrustedRoot, loadTrustedRootJson;

import 'trusted_root.dart';

export 'package:sigstore/sigstore.dart'
    hide loadTrustedRoot, loadTrustedRootJson;
export 'trusted_root.dart' show loadTrustedRoot, loadTrustedRootJson;

/// Attestation verifier in pub pre-configured with the Dart SDK's trusted root.
class PubAttestationVerifier extends AttestationVerifier {
  PubAttestationVerifier({String? overrideTrustedRootPath})
    : super(
        trustedRoot: loadTrustedRoot(overridePath: overrideTrustedRootPath),
      );
}
