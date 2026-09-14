// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import '../system_cache.dart';
import 'default_trusted_root.dart';
import 'sigstore.dart';
import 'trusted_root.dart';

export 'lockfile_policy.dart';
export 'sigstore.dart';
export 'trusted_root.dart';

/// Attestation verifier in pub pre-configured with the Sigstore trusted root.
class PubAttestationVerifier {
  final SystemCache? _cache;
  final String? _overrideTrustedRootPath;
  final String? _overrideTrustedRootJson;
  final bool _offline;

  PubAttestationVerifier({
    SystemCache? cache,
    String? overrideTrustedRootPath,
    String? overrideTrustedRootJson,
    bool offline = true,
  }) : _cache = cache,
       _overrideTrustedRootPath = overrideTrustedRootPath,
       _overrideTrustedRootJson = overrideTrustedRootJson,
       _offline = offline;

  /// Whether verification runs in offline mode.
  bool get offline => _offline;

  AttestationVerificationResult verify({
    required String packageName,
    required Version packageVersion,
    required List<int> archiveBytes,
    required SigstoreBundle bundle,
    String? expectedRepository,
    String? pubspecRepository,
  }) {
    try {
      var trustedRootJsonStr = _overrideTrustedRootJson ?? '';
      if (trustedRootJsonStr.isEmpty) {
        trustedRootJsonStr =
            loadTrustedRootJson(
              cache: _cache,
              overridePath: _overrideTrustedRootPath,
            ) ??
            defaultProductionTrustedRootJson;
      }
      final trustedRootMap =
          jsonDecode(trustedRootJsonStr) as Map<String, dynamic>;

      return PureDartSigstoreVerifier.verify(
        packageName: packageName,
        packageVersion: packageVersion,
        archiveBytes: archiveBytes,
        bundle: bundle,
        trustedRootJson: trustedRootMap,
        expectedRepository: expectedRepository ?? pubspecRepository,
      );
    } catch (e) {
      return AttestationVerificationResult(
        isValid: false,
        packageName: packageName,
        packageVersion: packageVersion,
        errors: [e.toString()],
      );
    }
  }
}
