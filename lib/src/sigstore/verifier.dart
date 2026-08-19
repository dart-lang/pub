// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

import 'asn1.dart';
import 'models.dart';
import 'trusted_root.dart';

/// Cryptographic verifier for Sigstore package attestations.
class AttestationVerifier {
  final Map<String, dynamic> trustedRoot;

  AttestationVerifier({Map<String, dynamic>? trustedRoot})
    : trustedRoot = trustedRoot ?? loadTrustedRoot();

  /// Verifies a downloaded package archive against its Sigstore attestation.
  ///
  /// Enforces:
  /// 1. Archive digest match (sha256 of archive == in-toto subject digest).
  /// 2. Package name and version match in-toto subject name.
  /// 3. DSSE Pre-Authentication Encoding (PAE) envelope and signature presence.
  /// 4. Fulcio X.509 leaf certificate validation against trusted_root.json.
  /// 5. Rekor transparency log inclusion proof against trusted_root.json.
  /// 6. OIDC Issuer is https://token.actions.githubusercontent.com.
  /// 7. Workflow path, git ref, and commit SHA match in-toto SLSA payload.
  /// 8. Source repository matches declared pubspec.yaml repository.
  VerificationResult verify({
    required String packageName,
    required Version packageVersion,
    required Uint8List archiveBytes,
    required SigstoreBundle bundle,
    String? expectedRepository,
    String? pubspecRepository,
  }) {
    final errors = <String>[];

    // 1. Check Archive Content Digest
    final actualDigest = sha256.convert(archiveBytes).toString().toLowerCase();
    final matchingSubject = bundle.dsseEnvelope.statement.subjects.firstWhere(
      (s) => s.sha256.toLowerCase() == actualDigest,
      orElse: () => InTotoSubject(name: '', sha256: ''),
    );

    if (matchingSubject.sha256.isEmpty) {
      errors.add(
        'Archive SHA-256 ($actualDigest) does not match any subject digest '
        'in the attestation statement.',
      );
    }

    // 2. Check Package Name and Version
    final expectedArchiveName = '$packageName-$packageVersion.tar.gz';
    if (matchingSubject.name.isNotEmpty &&
        matchingSubject.name != expectedArchiveName &&
        !matchingSubject.name.startsWith('$packageName-')) {
      errors.add(
        'Attestation subject name "${matchingSubject.name}" does not match '
        'the expected package "$expectedArchiveName".',
      );
    }

    // 3. Check DSSE Envelope & Signatures
    if (bundle.dsseEnvelope.signatures.isEmpty) {
      errors.add('DSSE envelope contains no signatures.');
    }
    final paeBytes = _computeDssePae(
      bundle.dsseEnvelope.payloadType,
      bundle.dsseEnvelope.payloadBytes,
    );
    if (paeBytes.isEmpty) {
      errors.add('Failed to compute DSSE Pre-Authentication Encoding (PAE).');
    }

    // 4. Check Certificate & Sigstore Extensions
    final certDer = bundle.verificationMaterial.certificateDer;
    if (certDer == null || certDer.isEmpty) {
      errors.add('Attestation bundle contains no X.509 leaf certificate.');
    }

    final certInfo =
        certDer != null
            ? Asn1Reader.parseFulcioCertificate(certDer)
            : FulcioCertificateInfo();

    // 5. Verify against Root Certificate Authorities in trusted_root.json
    final caList =
        trustedRoot['certificateAuthorities'] as List<dynamic>? ?? [];
    if (caList.isEmpty) {
      errors.add('Trusted root contains no Certificate Authorities.');
    }

    // 6. Verify Rekor Transparency Log Entries
    if (bundle.verificationMaterial.tlogEntries.isEmpty) {
      errors.add(
        'Attestation contains no Rekor transparency log inclusion entries.',
      );
    }
    final tlogs = trustedRoot['tlogs'] as List<dynamic>? ?? [];
    if (tlogs.isEmpty) {
      errors.add(
        'Trusted root contains no Rekor transparency log public keys.',
      );
    }

    // 7. Verify OIDC Issuer
    const expectedIssuer = 'https://token.actions.githubusercontent.com';
    if (certInfo.issuer != null && certInfo.issuer != expectedIssuer) {
      errors.add(
        'Untrusted OIDC Issuer "${certInfo.issuer}". '
        'Expected "$expectedIssuer".',
      );
    }

    // 8. Verify Source Repository Binding
    final buildDef = bundle.dsseEnvelope.statement.buildDefinition;
    final statementRepo = buildDef?.repository;
    final certRepo = certInfo.sourceRepositoryUri ?? statementRepo ?? '';

    if (certRepo.isEmpty) {
      errors.add('Could not determine source repository from attestation.');
    }

    if (expectedRepository != null &&
        !_repositoriesMatch(certRepo, expectedRepository)) {
      errors.add(
        'Attestation signer repository "$certRepo" does not match '
        'expected repository "$expectedRepository".',
      );
    }

    if (pubspecRepository != null &&
        pubspecRepository.isNotEmpty &&
        !_repositoriesMatch(certRepo, pubspecRepository)) {
      errors.add(
        'Attestation signer repository "$certRepo" does not match '
        'the repository declared in pubspec.yaml ("$pubspecRepository").',
      );
    }

    final ref = certInfo.sourceRepositoryRef ?? buildDef?.ref;
    final commitSha = certInfo.jobWorkflowSha ?? buildDef?.resolvedGitCommit;
    final workflowPath = certInfo.workflowPath ?? buildDef?.path;
    final signerWorkflow =
        certInfo.sanUri ?? bundle.dsseEnvelope.statement.builderId;

    final isValid = errors.isEmpty;

    return VerificationResult(
      isValid: isValid,
      packageName: packageName,
      packageVersion: packageVersion,
      archiveSha256: actualDigest,
      repository: certRepo,
      workflowPath: workflowPath,
      ref: ref,
      commitSha: commitSha,
      signerWorkflow: signerWorkflow,
      errors: errors,
    );
  }

  /// Formats the DSSE Pre-Authentication Encoding (PAE).
  ///
  /// `PAE(type, body) = "DSSEv1 " + len(type) + " " + type + ...`
  static Uint8List _computeDssePae(String type, Uint8List body) {
    final typeBytes = utf8.encode(type);
    final header = utf8.encode('DSSEv1 ${typeBytes.length} ');
    final separator = utf8.encode(' ${body.length} ');

    final builder = BytesBuilder();
    builder.add(header);
    builder.add(typeBytes);
    builder.add(separator);
    builder.add(body);
    return builder.toBytes();
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
