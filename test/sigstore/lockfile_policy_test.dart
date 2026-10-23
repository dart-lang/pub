// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/sigstore/verifier.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _repository = 'https://github.com/mosuem/helpful';
const _markerPath = '/pub-cache/hosted-provenance/pub.dev/helpful.provenance';

final _locked = LockedProvenance(_repository);
final _previouslyAttested = PreviouslyAttested(
  repository: _repository,
  since: Version(0, 1, 3),
  path: _markerPath,
);

void check({
  required ProvenanceInfo? verified,
  required AttestationExpectation? expectation,
  bool fatalOnRepositoryChange = false,
  void Function(String message)? onRepositoryChange,
}) {
  ProvenancePolicy.check(
    package: 'helpful',
    version: Version(0, 1, 4),
    verified: verified,
    expectation: expectation,
    repositoryUrl: 'https://pub.dev',
    fatalOnRepositoryChange: fatalOnRepositoryChange,
    onRepositoryChange: onRepositoryChange,
  );
}

void main() {
  test('accepts an unattested package when none is expected', () {
    expect(() => check(verified: null, expectation: null), returnsNormally);
  });

  test('accepts an attested package when none is expected', () {
    expect(
      () => check(
        verified: ProvenanceInfo(repository: _repository),
        expectation: null,
      ),
      returnsNormally,
    );
  });

  test('accepts an attested package from the expected repository', () {
    for (final expectation in [_locked, _previouslyAttested]) {
      expect(
        () => check(
          verified: ProvenanceInfo(repository: _repository),
          expectation: expectation,
        ),
        returnsNormally,
      );
    }
  });

  test('rejects an unattested package the lockfile has a provenance for', () {
    expect(
      () => check(verified: null, expectation: _locked),
      throwsA(
        isA<PackageProvenanceException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains(
              'helpful 0.1.4 is not attested, but an attestation is '
              'expected',
            ),
            contains('pubspec.lock records that helpful 0.1.4 was verified'),
            contains('`https://pub.dev` served no attestation'),
            contains(
              'remove the `provenance` entry of helpful from '
              'pubspec.lock',
            ),
          ),
        ),
      ),
    );
  });

  test('rejects an unattested version of a previously attested package', () {
    expect(
      () => check(verified: null, expectation: _previouslyAttested),
      throwsA(
        isA<PackageProvenanceException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('verified for helpful 0.1.3 on this machine'),
            contains('versions from 0.1.3 on are expected to be attested'),
            contains('delete `$_markerPath`'),
          ),
        ),
      ),
    );
  });

  test('reports a package built from another repository', () {
    final messages = <String>[];
    check(
      verified: ProvenanceInfo(repository: 'https://github.com/evil/helpful'),
      expectation: _locked,
      onRepositoryChange: messages.add,
    );
    expect(messages, hasLength(1));
    expect(
      messages.single,
      allOf(
        contains('attested as built from https://github.com/evil/helpful'),
        contains('pubspec.lock records'),
        contains(_repository),
      ),
    );
  });

  test('rejects a package built from another repository when fatal', () {
    expect(
      () => check(
        verified: ProvenanceInfo(repository: 'https://github.com/evil/helpful'),
        expectation: _previouslyAttested,
        fatalOnRepositoryChange: true,
      ),
      throwsA(isA<PackageProvenanceException>()),
    );
  });

  test('compares GitHub repositories by owner and name', () {
    expect(
      ProvenancePolicy.repositoriesMatch(
        'https://github.com/Mosuem/Helpful.git',
        'https://github.com/mosuem/helpful',
      ),
      isTrue,
    );
    expect(
      ProvenancePolicy.repositoriesMatch(
        'https://github.com/evil-mosuem/helpful',
        'https://github.com/mosuem/helpful',
      ),
      isFalse,
    );
    expect(
      ProvenancePolicy.repositoriesMatch(
        'https://gitlab.com/mosuem/helpful',
        'https://gitlab.com/mosuem/helpful',
      ),
      isTrue,
    );
  });
}
