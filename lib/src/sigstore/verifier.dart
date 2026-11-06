// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sigstore/provenance.dart';

import '../system_cache.dart';
import 'lockfile_policy.dart';
import 'sigstore.dart';
import 'trusted_root.dart';

export 'package:sigstore/provenance.dart';

export 'lockfile_policy.dart';
export 'sigstore.dart';
export 'trusted_root.dart';

/// The workflows trusted to sign attestations for packages on pub.dev, as
/// `<owner>/<repo>/<path>`.
///
/// This is the *signer* of an attestation - the reusable workflow that ran the
/// signing step - and not the repository a package was published from. All
/// packages are signed by the same small set of workflows, which is why the
/// signer identity says nothing about which package was built. That binding
/// comes from the provenance statement, see
/// [BuildProvenance.sourceRepository].
const defaultTrustedSignerWorkflows = <String>{
  'dart-lang/setup-dart/.github/workflows/publish.yml',
};

/// Result of verifying a package attestation bundle.
class AttestationVerificationResult {
  final bool isValid;
  final String packageName;
  final Version? packageVersion;

  /// The verified provenance, or `null` if verification failed.
  final ProvenanceInfo? provenance;

  /// The identity of the workflow that signed the attestation.
  final String? signerIdentity;
  final String? oidcIssuer;
  final List<String> errors;

  /// The repository the package was built from, or `null` if verification
  /// failed.
  String? get repository => provenance?.repository;

  AttestationVerificationResult({
    required this.isValid,
    required this.packageName,
    this.packageVersion,
    this.provenance,
    this.signerIdentity,
    this.oidcIssuer,
    this.errors = const [],
  });

  AttestationVerificationResult.failure({
    required this.packageName,
    this.packageVersion,
    this.signerIdentity,
    this.oidcIssuer,
    required this.errors,
  }) : isValid = false,
       provenance = null;
}

/// Attestation verifier in pub pre-configured with the Sigstore trusted root.
class PubAttestationVerifier {
  final SystemCache? _cache;
  final String? _overrideTrustedRootPath;
  final String? _overrideTrustedRootJson;
  final bool _offline;
  final Set<String> _trustedSignerWorkflows;
  final bool _requireTaggedSignerRef;

  PubAttestationVerifier({
    SystemCache? cache,
    String? overrideTrustedRootPath,
    String? overrideTrustedRootJson,
    bool offline = true,
    Set<String> trustedSignerWorkflows = defaultTrustedSignerWorkflows,
    // TODO(https://github.com/dart-lang/pub/issues/4942): Default to `true`
    // once the publishing workflow of `dart-lang/setup-dart` is released on a
    // tag. Until then any branch of that repository is accepted.
    bool requireTaggedSignerRef = false,
  }) : _cache = cache,
       _overrideTrustedRootPath = overrideTrustedRootPath,
       _overrideTrustedRootJson = overrideTrustedRootJson,
       _offline = offline,
       _trustedSignerWorkflows = trustedSignerWorkflows,
       _requireTaggedSignerRef = requireTaggedSignerRef;

  /// Verifies that the archive with the sha256 digest [archiveSha256] is the
  /// archive of [packageName] at
  /// [packageVersion], built by a trusted workflow from [expectedRepository].
  ///
  /// [bundleJson] is the Sigstore bundle as served by the package repository.
  /// It is passed as JSON (rather than as a parsed [SigstoreBundle]) so that
  /// the signature check and the inspection of the signed statement are
  /// guaranteed to happen on the same bytes.
  ///
  /// [expectedRepository] is the `repository:` field of the `pubspec.yaml`
  /// *inside* the archive. The pubspec of the version listing must not be
  /// used: only the archive is covered by the attested digest. If
  /// [requireRepository] is `true`, verification fails when
  /// [expectedRepository] is missing - an attestation that is not bound to a
  /// repository proves nothing beyond "somebody's trusted workflow built
  /// this".
  AttestationVerificationResult verify({
    required String packageName,
    required Version packageVersion,
    required List<int> archiveSha256,
    required String bundleJson,
    String? declaredPackageName,
    Version? declaredPackageVersion,
    String? expectedRepository,
    bool requireRepository = true,
  }) {
    if (archiveSha256.length != 32) {
      throw ArgumentError.value(
        archiveSha256,
        'archiveSha256',
        'must be a 32-byte sha256 digest',
      );
    }

    // Loaded outside of the `try` below: a missing or unreadable trusted root
    // is a local configuration problem, not a problem with the attestation,
    // and must not be reported as one. An empty string makes
    // `package:sigstore` fall back to its built-in production root of trust.
    final trustedRootJson =
        _overrideTrustedRootJson ??
        loadTrustedRootJson(
          cache: _cache,
          overridePath: _overrideTrustedRootPath,
        ) ??
        '';

    String? identity;
    String? issuer;
    try {
      // Throws [SigstoreError.invalidBundle], handled below.
      final bundle = SigstoreBundle.fromJson(bundleJson);

      final client = SigstoreClient.create();
      // The expected identity is left unrestricted here and enforced below
      // against [_trustedSignerWorkflows]: we accept a set of workflows, and
      // the ref they ran at varies. An empty string means "any identity" to
      // `package:sigstore`, so *this call alone does not authenticate the
      // signer*.
      final policy = SigstoreVerificationPolicy.create(
        '',
        githubActionsOidcIssuer,
        _offline,
        false,
        trustedRootJson,
        '',
      );

      // Verifying against the digest (`isDigest: true`): the archive was
      // already hashed while it was downloaded, and the subject digest of the
      // in-toto statement is compared against it.
      final result = client.verify(archiveSha256, true, bundle, policy);
      if (!result.isValid()) {
        return AttestationVerificationResult.failure(
          packageName: packageName,
          packageVersion: packageVersion,
          errors: ['Attestation signature verification failed'],
        );
      }

      identity = result.verifiedIdentity();
      issuer = result.verifiedIssuer();

      final signer = GitHubWorkflowIdentity.tryParse(identity);
      if (signer == null) {
        final message =
            'Package attestation verification is currently only supported for '
            'GitHub Actions workflows (signer identity: "$identity").';
        return AttestationVerificationResult.failure(
          packageName: packageName,
          packageVersion: packageVersion,
          signerIdentity: identity,
          oidcIssuer: issuer,
          errors: [message],
        );
      }

      final BuildProvenance provenance;
      try {
        provenance = BuildProvenance.parseBundle(bundleJson);
      } on FormatException catch (e) {
        return AttestationVerificationResult.failure(
          packageName: packageName,
          packageVersion: packageVersion,
          signerIdentity: identity,
          oidcIssuer: issuer,
          errors: [e.message],
        );
      }

      final errors = checkProvenancePolicy(
        packageName: packageName,
        packageVersion: packageVersion.toString(),
        archiveSha256: Digest(archiveSha256).toString(),
        provenance: provenance,
        signer: signer,
        oidcIssuer: issuer,
        declaredPackageName: declaredPackageName,
        declaredPackageVersion: declaredPackageVersion?.toString(),
        expectedRepository: expectedRepository,
        requireRepository: requireRepository,
        trustedSignerWorkflows: _trustedSignerWorkflows,
        requireTaggedSignerRef: _requireTaggedSignerRef,
      );
      if (errors.isNotEmpty) {
        return AttestationVerificationResult.failure(
          packageName: packageName,
          packageVersion: packageVersion,
          signerIdentity: identity,
          oidcIssuer: issuer,
          errors: errors,
        );
      }

      return AttestationVerificationResult(
        isValid: true,
        packageName: packageName,
        packageVersion: packageVersion,
        provenance: ProvenanceInfo(
          repository: provenance.sourceRepository.url,
          ref: provenance.sourceRef,
          commitSha: provenance.commitSha,
          workflowPath: provenance.workflowPath,
        ),
        signerIdentity: identity,
        oidcIssuer: issuer,
      );
    } on SigstoreError catch (e) {
      // `package:sigstore` reports failures by throwing this enum - including
      // an unsuccessful verification, which does not come back as a
      // `SigstoreVerificationResult` with `isValid() == false`.
      return AttestationVerificationResult.failure(
        packageName: packageName,
        packageVersion: packageVersion,
        signerIdentity: identity,
        oidcIssuer: issuer,
        errors: [
          switch (e) {
            SigstoreError.invalidBundle =>
              'Attestation is not a valid '
                  'Sigstore bundle.',
            SigstoreError.verificationFailed =>
              'Attestation signature verification failed.',
            SigstoreError.internalError =>
              'Internal error while verifying the attestation.',
          },
        ],
      );
      // `package:sigstore` signals a missing `dart:ffi` by throwing an
      // `UnsupportedError`. The catch-all below would handle it too, but
      // catching it explicitly lets us explain to the user that the platform,
      // rather than the attestation, is at fault.
      // ignore: avoid_catching_errors
    } on UnsupportedError catch (e) {
      return AttestationVerificationResult.failure(
        packageName: packageName,
        packageVersion: packageVersion,
        signerIdentity: identity,
        oidcIssuer: issuer,
        errors: [
          'Attestations cannot be verified on this platform: ${e.message}',
        ],
      );
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      // Anything unexpected must fail verification, never pass it.
      return AttestationVerificationResult.failure(
        packageName: packageName,
        packageVersion: packageVersion,
        signerIdentity: identity,
        oidcIssuer: issuer,
        errors: [e.toString()],
      );
    }
  }
}
