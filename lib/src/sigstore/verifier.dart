// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

import '../system_cache.dart';
import 'lockfile_policy.dart';
import 'provenance.dart';
import 'sigstore.dart';
import 'trusted_root.dart';

export 'lockfile_policy.dart';
export 'provenance.dart';
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
    bool requireTaggedSignerRef = false,
  }) : _cache = cache,
       _overrideTrustedRootPath = overrideTrustedRootPath,
       _overrideTrustedRootJson = overrideTrustedRootJson,
       _offline = offline,
       _trustedSignerWorkflows = trustedSignerWorkflows,
       _requireTaggedSignerRef = requireTaggedSignerRef;

  /// Verifies that [archiveBytes] is the archive of [packageName] at
  /// [packageVersion], built by a trusted workflow from [expectedRepository].
  ///
  /// [bundleJson] is the Sigstore bundle as served by the package repository.
  /// It is passed as JSON (rather than as a parsed [SigstoreBundle]) so that
  /// the signature check and the inspection of the signed statement are
  /// guaranteed to happen on the same bytes.
  ///
  /// [expectedRepository] is the `repository:` field of the `pubspec.yaml`
  /// *inside* [archiveBytes]. The pubspec of the version listing must not be
  /// used: only the archive is covered by the attested digest. If
  /// [requireRepository] is `true`, verification fails when
  /// [expectedRepository] is missing - an attestation that is not bound to a
  /// repository proves nothing beyond "somebody's trusted workflow built
  /// this".
  AttestationVerificationResult verify({
    required String packageName,
    required Version packageVersion,
    required List<int> archiveBytes,
    required String bundleJson,
    String? declaredPackageName,
    Version? declaredPackageVersion,
    String? expectedRepository,
    bool requireRepository = true,
  }) {
    String? identity;
    String? issuer;
    try {
      // A `null` trusted root makes `package:sigstore` fall back to its
      // built-in production root of trust.
      final trustedRootJson =
          _overrideTrustedRootJson ??
          loadTrustedRootJson(
            cache: _cache,
            overridePath: _overrideTrustedRootPath,
          ) ??
          '';

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

      final result = client.verify(archiveBytes, false, bundle, policy);
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
        packageVersion: packageVersion,
        archiveSha256: sha256.convert(archiveBytes).toString(),
        provenance: provenance,
        signer: signer,
        oidcIssuer: issuer,
        declaredPackageName: declaredPackageName,
        declaredPackageVersion: declaredPackageVersion,
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

/// Checks a cryptographically verified attestation against pub's policy, and
/// returns the list of violations - empty if the attestation is acceptable.
///
/// [archiveSha256] is the lowercase hex-encoded sha256 of the archive, and
/// [signer] the identity from the signing certificate. Both must come from
/// verified material.
///
/// This is separate from [PubAttestationVerifier.verify] so that the policy can
/// be exercised without doing (or faking) cryptographic verification.
List<String> checkProvenancePolicy({
  required String packageName,
  required Version packageVersion,
  required String archiveSha256,
  required BuildProvenance provenance,
  required GitHubWorkflowIdentity signer,
  String? oidcIssuer,
  String? declaredPackageName,
  Version? declaredPackageVersion,
  String? expectedRepository,
  bool requireRepository = true,
  Set<String> trustedSignerWorkflows = defaultTrustedSignerWorkflows,
  bool requireTaggedSignerRef = false,
}) {
  final errors = <String>[];

  if (oidcIssuer != null && oidcIssuer != githubActionsOidcIssuer) {
    errors.add(
      'Attestation was issued by "$oidcIssuer", '
      'expected "$githubActionsOidcIssuer".',
    );
  }

  // Who signed? Only a small set of workflows may sign packages for pub.dev.
  final trusted = trustedSignerWorkflows.map((w) => w.toLowerCase()).toSet();
  if (!trusted.contains(signer.workflow.toLowerCase())) {
    errors.add(
      'Attestation was signed by "${signer.workflow}", which is not a '
      'workflow trusted to publish packages. Trusted workflows: '
      '${(trustedSignerWorkflows.toList()..sort()).join(', ')}.',
    );
  } else if (requireTaggedSignerRef && !signer.ref.startsWith('refs/tags/')) {
    // TODO(sigurdm): Pin the signing workflow by the `job_workflow_sha`
    // certificate extension (OID 1.3.6.1.4.1.57264.1.20) once
    // `package:sigstore` exposes it. A ref is mutable, a sha is not.
    errors.add(
      'Attestation was signed by "${signer.workflow}" at "${signer.ref}", '
      'but only tagged releases of the publishing workflow are trusted.',
    );
  } else if (!signer.ref.startsWith('refs/tags/') &&
      !signer.ref.startsWith('refs/heads/')) {
    errors.add(
      'Attestation was signed by "${signer.workflow}" at "${signer.ref}", '
      'which is not a branch or tag ref.',
    );
  }
  final builder = provenance.builder;
  if (builder != null &&
      builder.workflow.toLowerCase() != signer.workflow.toLowerCase()) {
    errors.add(
      'Attestation states it was built by "${builder.workflow}" but was '
      'signed by "${signer.workflow}".',
    );
  }

  // What was signed? Without this an attestation for one package could be
  // served for another - all packages share the same signer identity.
  // `dart-lang/setup-dart` names the archive `package.tar.gz`, so the package
  // name and version are bound through the `pubspec.yaml` inside the archive
  // (covered by `archiveSha256`).
  final expectedSubject = '$packageName-$packageVersion.tar.gz';
  final subject =
      provenance.subjects
          .where((s) => s.name == expectedSubject || s.name == 'package.tar.gz')
          .firstOrNull;
  if (subject == null) {
    errors.add(
      'Attestation is for '
      '${provenance.subjects.map((s) => '"${s.name}"').join(', ')}, '
      'not for "$expectedSubject".',
    );
  } else if (subject.sha256 != archiveSha256.toLowerCase()) {
    errors.add(
      'Attestation is for an archive with sha256 "${subject.sha256}", '
      'but the downloaded archive has sha256 "$archiveSha256".',
    );
  }

  if (declaredPackageName != null && declaredPackageName != packageName) {
    errors.add(
      'The pubspec.yaml of the attested archive declares `name: '
      '$declaredPackageName`, expected `$packageName`.',
    );
  }
  if (declaredPackageVersion != null &&
      declaredPackageVersion != packageVersion) {
    errors.add(
      'The pubspec.yaml of the attested archive declares `version: '
      '$declaredPackageVersion`, expected `$packageVersion`.',
    );
  }

  // Where was it built? This is the binding the whole feature rests on.
  if (expectedRepository == null || expectedRepository.trim().isEmpty) {
    if (requireRepository) {
      errors.add(
        'The pubspec.yaml of $packageName $packageVersion does not have a '
        '`repository` field, so the attestation cannot be bound to the '
        'repository it claims to come from '
        '("${provenance.sourceRepository.url}").',
      );
    }
  } else {
    final expected = GitHubRepository.tryParse(expectedRepository);
    if (expected == null) {
      errors.add(
        'Package attestation verification is currently only supported for '
        'GitHub repositories, but the pubspec.yaml of $packageName '
        '$packageVersion declares `repository: $expectedRepository`.',
      );
    } else if (expected != provenance.sourceRepository) {
      errors.add(
        'Attestation states the package was built from '
        '"${provenance.sourceRepository.url}", but the pubspec.yaml of '
        '$packageName $packageVersion declares `repository: '
        '$expectedRepository`.',
      );
    }
  }

  return errors;
}
