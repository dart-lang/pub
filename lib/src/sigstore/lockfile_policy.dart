// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../log.dart' as log;
import 'models.dart';

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
  }) {
    if (previousLockedProvenance != null && currentProvenance == null) {
      throw PackageIntegrityException('''
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
          throw PackageIntegrityException(
            '$message\n'
            'Repository changes for signed packages require verification.',
          );
        } else {
          log.warning(message);
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
