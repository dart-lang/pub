// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/sigstore/verifier.dart';
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
      throwsA(isA<PackageProvenanceException>()),
    );
  });

  test('detects repository switch and emits warning by default', () {
    final prev = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.3',
    );
    final current = ProvenanceInfo(
      repository: 'https://github.com/newowner/helpful',
      ref: 'refs/tags/v0.1.4',
    );

    final warnings = <String>[];
    ProvenancePolicy.enforcePolicy(
      packageName: 'helpful',
      version: Version(0, 1, 4),
      currentProvenance: current,
      previousLockedProvenance: prev,
      onWarning: warnings.add,
    );

    expect(warnings, hasLength(1));
    expect(warnings.first, contains('provenance repository changed'));
  });

  test('allows installing unsigned package when no previous lock exists', () {
    expect(
      () => ProvenancePolicy.enforcePolicy(
        packageName: 'helpful',
        version: Version(0, 1, 4),
        currentProvenance: null,
        previousLockedProvenance: null,
      ),
      returnsNormally,
    );
  });

  test('allows upgrading from unsigned to signed package', () {
    final current = ProvenanceInfo(
      repository: 'https://github.com/mosuem/helpful',
      ref: 'refs/tags/v0.1.4',
    );

    expect(
      () => ProvenancePolicy.enforcePolicy(
        packageName: 'helpful',
        version: Version(0, 1, 4),
        currentProvenance: current,
        previousLockedProvenance: null,
      ),
      returnsNormally,
    );
  });
}
