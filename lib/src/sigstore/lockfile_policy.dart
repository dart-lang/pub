// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

/// Exception thrown when package integrity or provenance policies fail.
class PackageProvenanceException implements Exception {
  final String message;
  PackageProvenanceException(this.message);

  @override
  String toString() => message;
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

/// Enforces security policies between the current package and previous locks.
class ProvenancePolicy {
  /// Enforces downgrade prevention and repository continuity.
  ///
  /// 1. Downgrade attack prevention: If [packageName] was previously locked
  ///    with signed provenance ([previousLockedProvenance] != null),
  ///    subsequent versions must also have valid signed provenance
  ///    ([currentProvenance] != null).
  ///
  /// 2. Repository switch alert: If the repository changes from
  ///    [previousLockedProvenance], a security warning or error is issued.
  static void enforcePolicy({
    required String packageName,
    required Version version,
    required ProvenanceInfo? currentProvenance,
    required ProvenanceInfo? previousLockedProvenance,
    bool fatalOnRepoMismatch = false,
    void Function(String message)? onWarning,
  }) {
    if (previousLockedProvenance != null && currentProvenance == null) {
      throw PackageProvenanceException('''
Package "$packageName" version $version is not signed with provenance.
However, previously locked versions of this package were signed by:
  ${previousLockedProvenance.repository}

Downgrading from a signed package to an unsigned package is prohibited.
''');
    }

    if (previousLockedProvenance != null && currentProvenance != null) {
      if (!_repositoriesMatch(
        previousLockedProvenance.repository,
        currentProvenance.repository,
      )) {
        final message =
            'Package "$packageName" provenance repository changed from '
            '"${previousLockedProvenance.repository}" to '
            '"${currentProvenance.repository}".';
        if (fatalOnRepoMismatch) {
          throw PackageProvenanceException(
            '$message\n'
            'Repository changes for signed packages require verification.',
          );
        } else if (onWarning != null) {
          onWarning(message);
        }
      }
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
