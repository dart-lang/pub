// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';

/// Parsed Sigstore bundle.
class SigstoreBundle {
  final String mediaType;
  final VerificationMaterial verificationMaterial;
  final DsseEnvelope dsseEnvelope;

  SigstoreBundle({
    required this.mediaType,
    required this.verificationMaterial,
    required this.dsseEnvelope,
  });

  factory SigstoreBundle.fromJson(Map<String, dynamic> json) {
    final mediaType = json['mediaType'] as String? ?? '';
    final vMaterial = json['verificationMaterial'] as Map<String, dynamic>?;
    final dsse = json['dsseEnvelope'] as Map<String, dynamic>?;

    if (vMaterial == null || dsse == null) {
      throw DataException(
        'Invalid Sigstore bundle format: '
        'missing verificationMaterial or dsseEnvelope.',
      );
    }

    return SigstoreBundle(
      mediaType: mediaType,
      verificationMaterial: VerificationMaterial.fromJson(vMaterial),
      dsseEnvelope: DsseEnvelope.fromJson(dsse),
    );
  }
}

/// Verification material containing the certificate and transparency logs.
class VerificationMaterial {
  final Uint8List? certificateDer;
  final String? certificatePem;
  final List<TlogEntry> tlogEntries;

  VerificationMaterial({
    this.certificateDer,
    this.certificatePem,
    required this.tlogEntries,
  });

  factory VerificationMaterial.fromJson(Map<String, dynamic> json) {
    Uint8List? certDer;
    String? certPem;

    if (json['certificate'] case final Map<String, dynamic> certMap) {
      if (certMap['rawBytes'] case final String rawBytesBase64) {
        certDer = base64Decode(rawBytesBase64);
      }
    } else if (json['x509CertificateChain']
        case final Map<String, dynamic> chainMap) {
      if (chainMap['certificates'] case final List<dynamic> certList) {
        if (certList.isNotEmpty && certList.first is Map) {
          final first = certList.first as Map<String, dynamic>;
          if (first['rawBytes'] case final String rawBytes) {
            certDer = base64Decode(rawBytes);
          }
        }
      }
    }

    final tlogList = json['tlogEntries'] as List<dynamic>? ?? [];
    final tlogs =
        tlogList
            .map((e) => TlogEntry.fromJson(e as Map<String, dynamic>))
            .toList();

    return VerificationMaterial(
      certificateDer: certDer,
      certificatePem: certPem,
      tlogEntries: tlogs,
    );
  }
}

/// A Rekor transparency log entry.
class TlogEntry {
  final String logIndex;
  final String? rootHash;
  final List<String> inclusionHashes;
  final String? canonicalizedBody;

  TlogEntry({
    required this.logIndex,
    this.rootHash,
    required this.inclusionHashes,
    this.canonicalizedBody,
  });

  factory TlogEntry.fromJson(Map<String, dynamic> json) {
    final logIndex = json['logIndex']?.toString() ?? '';
    final inclusionProof = json['inclusionProof'] as Map<String, dynamic>?;
    final rootHash = inclusionProof?['rootHash'] as String?;
    final hashesList = inclusionProof?['hashes'] as List<dynamic>? ?? [];
    final hashes = hashesList.map((e) => e.toString()).toList();
    final canonicalizedBody = json['canonicalizedBody'] as String?;

    return TlogEntry(
      logIndex: logIndex,
      rootHash: rootHash,
      inclusionHashes: hashes,
      canonicalizedBody: canonicalizedBody,
    );
  }
}

/// DSSE envelope containing the signed in-toto statement payload and
/// signatures.
class DsseEnvelope {
  final String payloadType;
  final String payloadBase64;
  final Uint8List payloadBytes;
  final List<DsseSignature> signatures;
  final InTotoStatement statement;

  DsseEnvelope({
    required this.payloadType,
    required this.payloadBase64,
    required this.payloadBytes,
    required this.signatures,
    required this.statement,
  });

  factory DsseEnvelope.fromJson(Map<String, dynamic> json) {
    final payloadType = json['payloadType'] as String? ?? '';
    final payloadBase64 = json['payload'] as String? ?? '';
    final payloadBytes = base64Decode(payloadBase64);
    final payloadJson =
        jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    final statement = InTotoStatement.fromJson(payloadJson);

    final sigsList = json['signatures'] as List<dynamic>? ?? [];
    final signatures =
        sigsList
            .map((e) => DsseSignature.fromJson(e as Map<String, dynamic>))
            .toList();

    return DsseEnvelope(
      payloadType: payloadType,
      payloadBase64: payloadBase64,
      payloadBytes: payloadBytes,
      signatures: signatures,
      statement: statement,
    );
  }
}

/// A signature inside a DSSE envelope.
class DsseSignature {
  final String? keyid;
  final String sigBase64;
  final Uint8List sigBytes;

  DsseSignature({this.keyid, required this.sigBase64, required this.sigBytes});

  factory DsseSignature.fromJson(Map<String, dynamic> json) {
    final sigBase64 = json['sig'] as String? ?? '';
    return DsseSignature(
      keyid: json['keyid'] as String?,
      sigBase64: sigBase64,
      sigBytes: base64Decode(sigBase64),
    );
  }
}

/// Parsed in-toto statement payload.
class InTotoStatement {
  final String type;
  final String predicateType;
  final List<InTotoSubject> subjects;
  final Map<String, dynamic> predicate;
  final SlsaBuildDefinition? buildDefinition;
  final String? builderId;

  InTotoStatement({
    required this.type,
    required this.predicateType,
    required this.subjects,
    required this.predicate,
    this.buildDefinition,
    this.builderId,
  });

  factory InTotoStatement.fromJson(Map<String, dynamic> json) {
    final type = json['_type'] as String? ?? '';
    final predicateType = json['predicateType'] as String? ?? '';
    final subjectsList = json['subject'] as List<dynamic>? ?? [];
    final subjects =
        subjectsList
            .map((e) => InTotoSubject.fromJson(e as Map<String, dynamic>))
            .toList();
    final predicate = json['predicate'] as Map<String, dynamic>? ?? {};

    SlsaBuildDefinition? buildDef;
    String? builderId;

    if (predicate['buildDefinition'] case final Map<String, dynamic> bdMap) {
      buildDef = SlsaBuildDefinition.fromJson(bdMap);
    }
    if (predicate['runDetails'] case final Map<String, dynamic> rdMap) {
      if (rdMap['builder'] case final Map<String, dynamic> bMap) {
        builderId = bMap['id'] as String?;
      }
    }

    return InTotoStatement(
      type: type,
      predicateType: predicateType,
      subjects: subjects,
      predicate: predicate,
      buildDefinition: buildDef,
      builderId: builderId,
    );
  }
}

/// An artifact subject inside an in-toto statement.
class InTotoSubject {
  final String name;
  final String sha256;

  InTotoSubject({required this.name, required this.sha256});

  factory InTotoSubject.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final digest = json['digest'] as Map<String, dynamic>? ?? {};
    final sha256 = digest['sha256'] as String? ?? '';
    return InTotoSubject(name: name, sha256: sha256);
  }
}

/// SLSA build definition details.
class SlsaBuildDefinition {
  final String? buildType;
  final String? repository;
  final String? ref;
  final String? path;
  final String? resolvedGitCommit;

  SlsaBuildDefinition({
    this.buildType,
    this.repository,
    this.ref,
    this.path,
    this.resolvedGitCommit,
  });

  factory SlsaBuildDefinition.fromJson(Map<String, dynamic> json) {
    final buildType = json['buildType'] as String?;
    String? repo;
    String? ref;
    String? path;
    String? gitCommit;

    if (json['externalParameters'] case final Map<String, dynamic> extMap) {
      if (extMap['workflow'] case final Map<String, dynamic> wfMap) {
        repo = wfMap['repository'] as String?;
        ref = wfMap['ref'] as String?;
        path = wfMap['path'] as String?;
      }
    }

    if (json['resolvedDependencies'] case final List<dynamic> depsList) {
      if (depsList.isNotEmpty && depsList.first is Map) {
        final first = depsList.first as Map<String, dynamic>;
        if (first['digest'] case final Map<String, dynamic> digestMap) {
          gitCommit = digestMap['gitCommit'] as String?;
        }
      }
    }

    return SlsaBuildDefinition(
      buildType: buildType,
      repository: repo,
      ref: ref,
      path: path,
      resolvedGitCommit: gitCommit,
    );
  }
}

/// Information parsed from Fulcio X.509 certificate extensions.
class FulcioCertificateInfo {
  final String? issuer;
  final String? sourceRepositoryUri;
  final String? sourceRepositoryRef;
  final String? workflowPath;
  final String? jobWorkflowSha;
  final String? runnerEnvironment;
  final String? sanUri;

  FulcioCertificateInfo({
    this.issuer,
    this.sourceRepositoryUri,
    this.sourceRepositoryRef,
    this.workflowPath,
    this.jobWorkflowSha,
    this.runnerEnvironment,
    this.sanUri,
  });
}

/// Result of attestation verification.
class VerificationResult {
  final bool isValid;
  final String packageName;
  final Version packageVersion;
  final String archiveSha256;
  final String repository;
  final String? workflowPath;
  final String? ref;
  final String? commitSha;
  final String? signerWorkflow;
  final List<String> errors;

  VerificationResult({
    required this.isValid,
    required this.packageName,
    required this.packageVersion,
    required this.archiveSha256,
    required this.repository,
    this.workflowPath,
    this.ref,
    this.commitSha,
    this.signerWorkflow,
    this.errors = const [],
  });

  ProvenanceInfo toProvenanceInfo() {
    return ProvenanceInfo(
      repository: repository,
      ref: ref,
      commitSha: commitSha,
      workflowPath: workflowPath,
    );
  }
}

/// Compact provenance summary stored in memory or lockfile.
class ProvenanceInfo {
  final String repository;
  final String? ref;
  final String? commitSha;
  final String? workflowPath;

  ProvenanceInfo({
    required this.repository,
    this.ref,
    this.commitSha,
    this.workflowPath,
  });

  Map<String, dynamic> toJson() => {
    'repository': repository,
    if (ref != null) 'ref': ref,
    if (commitSha != null) 'commitSha': commitSha,
    if (workflowPath != null) 'workflowPath': workflowPath,
  };

  factory ProvenanceInfo.fromJson(Map<String, dynamic> json) {
    return ProvenanceInfo(
      repository: json['repository'] as String? ?? '',
      ref: json['ref'] as String?,
      commitSha: json['commitSha'] as String?,
      workflowPath: json['workflowPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProvenanceInfo &&
      repository == other.repository &&
      ref == other.ref &&
      commitSha == other.commitSha &&
      workflowPath == other.workflowPath;

  @override
  int get hashCode => Object.hash(repository, ref, commitSha, workflowPath);
}
