// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exceptions.dart';
import 'package:pub/src/sigstore/lockfile_policy.dart';
import 'package:pub/src/sigstore/models.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('allows signed package when previously locked version was signed', () {
    final prev = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.3',
    );
    final current = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.4',
    );

    expect(
      () => ProvenancePolicy.enforcePolicy(
        packageName: 'helpful',
        version: Version(0, 1, 4),
        currentProvenance: current,
        previousLockedProvenance: prev,
      ),
      returnsNormally,
    );
  });

  test('blocks downgrade attack when new version is unsigned', () {
    final prev = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.3',
    );

    expect(
      () => ProvenancePolicy.enforcePolicy(
        packageName: 'helpful',
        version: Version(0, 1, 4),
        currentProvenance: null,
        previousLockedProvenance: prev,
      ),
      throwsA(isA<PackageIntegrityException>()),
    );
  });

  test('detects repository switch when configured as fatal', () {
    final prev = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.3',
    );
    final current = ProvenanceInfo(
      repository: 'https://github.com/attacker/helpful',
      ref: 'refs/tags/v0.1.4',
    );

    expect(
      () => ProvenancePolicy.enforcePolicy(
        packageName: 'helpful',
        version: Version(0, 1, 4),
        currentProvenance: current,
        previousLockedProvenance: prev,
        fatalOnRepoMismatch: true,
      ),
      throwsA(isA<PackageIntegrityException>()),
    );
  });
}
