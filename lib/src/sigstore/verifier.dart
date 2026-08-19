// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:sigstore/sigstore.dart';

import '../system_cache.dart';

export 'package:sigstore/sigstore.dart';
export 'lockfile_policy.dart';
export 'trusted_root.dart';

/// Result of verifying a package attestation bundle.
class AttestationVerificationResult {
  final bool isValid;
  final String packageName;
  final Version? packageVersion;
  final String? repository;
  final String? signerIdentity;
  final String? oidcIssuer;
  final List<String> errors;

  AttestationVerificationResult({
    required this.isValid,
    required this.packageName,
    this.packageVersion,
    this.repository,
    this.signerIdentity,
    this.oidcIssuer,
    this.errors = const [],
  });
}

/// Attestation verifier in pub pre-configured with the Dart SDK's trusted root.
class PubAttestationVerifier {
  final String? _trustedRootPath;
  final String? _overrideTrustedRootJson;
  final bool _offline;

  PubAttestationVerifier({
    SystemCache? cache,
    String? overrideTrustedRootPath,
    String? overrideTrustedRootJson,
    bool offline = true,
  })  : _trustedRootPath =
            overrideTrustedRootPath ?? cache?.sigstoreTrustedRootPath,
        _overrideTrustedRootJson = overrideTrustedRootJson,
        _offline = offline;

  AttestationVerificationResult verify({
    required String packageName,
    required Version packageVersion,
    required List<int> archiveBytes,
    required SigstoreBundle bundle,
    String? expectedRepository,
    String? pubspecRepository,
  }) {
    try {
      var trustedRootJson = _overrideTrustedRootJson ?? '';
      if (trustedRootJson.isEmpty && _trustedRootPath != null) {
        final f = File(_trustedRootPath);
        if (f.existsSync()) {
          trustedRootJson = f.readAsStringSync();
        }
      }

      final client = SigstoreClient.create();
      final policy = SigstoreVerificationPolicy.create(
        '',
        'https://token.actions.githubusercontent.com',
        _offline,
        false,
        trustedRootJson,
        '',
      );

      final result = client.verify(archiveBytes, false, bundle, policy);
      if (!result.isValid()) {
        return AttestationVerificationResult(
          isValid: false,
          packageName: packageName,
          packageVersion: packageVersion,
          errors: ['Attestation signature verification failed'],
        );
      }

      final identity = result.verifiedIdentity();
      final issuer = result.verifiedIssuer();
      String? repo;
      if (identity.startsWith('https://github.com/')) {
        final parts =
            identity.substring('https://github.com/'.length).split('/');
        if (parts.length >= 2) {
          repo = 'https://github.com/${parts[0]}/${parts[1]}';
        }
      }

      final targetRepo = expectedRepository ?? pubspecRepository;
      if (targetRepo != null && targetRepo.isNotEmpty) {
        if (repo == null || !_repositoriesMatch(repo, targetRepo)) {
          final msg =
              'Attestation identity "$identity" does not match expected '
              'repository "$targetRepo"';
          return AttestationVerificationResult(
            isValid: false,
            packageName: packageName,
            packageVersion: packageVersion,
            repository: repo,
            signerIdentity: identity,
            oidcIssuer: issuer,
            errors: [msg],
          );
        }
      }

      return AttestationVerificationResult(
        isValid: true,
        packageName: packageName,
        packageVersion: packageVersion,
        repository: repo ?? targetRepo,
        signerIdentity: identity,
        oidcIssuer: issuer,
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

  static bool _repositoriesMatch(String a, String b) {
    final normA = a
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\.git$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    final normB = b
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\.git$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return normA == normB || normA.endsWith(normB) || normB.endsWith(normA);
  }
}
