// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:pub/src/sigstore/verifier.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  test('verifies a real signed package attestation (helpful 0.1.5)', () {
    final verifier = PubAttestationVerifier();

    final result = verifier.verify(
      packageName: 'helpful',
      packageVersion: Version(0, 1, 5),
      archiveBytes: helpfulArchiveBytes,
      bundleJson: helpfulBundleJson,
      declaredPackageName: 'helpful',
      declaredPackageVersion: Version(0, 1, 5),
      expectedRepository: 'https://github.com/mosuem/helpful',
    );

    expect(result.errors, isEmpty);
    expect(result.isValid, isTrue);
    expect(result.repository, 'https://github.com/mosuem/helpful');
    expect(
      result.provenance?.commitSha,
      '63216a3022ed606538399634cd1c525f8bd4657f',
    );
  });

  test('rejects a real attestation when served for another package', () {
    final verifier = PubAttestationVerifier();

    final result = verifier.verify(
      packageName: 'evil',
      packageVersion: Version(0, 1, 5),
      archiveBytes: helpfulArchiveBytes,
      bundleJson: helpfulBundleJson,
      declaredPackageName: 'helpful',
      declaredPackageVersion: Version(0, 1, 5),
      expectedRepository: 'https://github.com/mosuem/helpful',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.single,
      contains('declares `name: helpful`, expected `evil`'),
    );
  });

  test(
    'rejects a real attestation when pubspec declares another repository',
    () {
      final verifier = PubAttestationVerifier();

      final result = verifier.verify(
        packageName: 'helpful',
        packageVersion: Version(0, 1, 5),
        archiveBytes: helpfulArchiveBytes,
        bundleJson: helpfulBundleJson,
        declaredPackageName: 'helpful',
        declaredPackageVersion: Version(0, 1, 5),
        expectedRepository: 'https://github.com/evil/helpful',
      );

      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('was built from'));
    },
  );

  test('rejects a bundle that carries no build provenance', () {
    // This bundle is cryptographically valid, and was produced by a GitHub
    // Actions workflow - but it is a plain artifact signature over some other
    // file, made by an unrelated repository. Accepting it would mean accepting
    // any valid bundle from any workflow as the attestation of any package.
    final verifier = PubAttestationVerifier();

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: sampleArtifactBytes,
      bundleJson: sampleBundleJson,
      expectedRepository:
          'https://github.com/sigstore-conformance/'
          'extremely-dangerous-public-oidc-beacon',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.single, contains('carries no build provenance'));
  });

  test('fails when archive bytes do not match attestation', () {
    final verifier = PubAttestationVerifier();

    final tamperedBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: tamperedBytes,
      bundleJson: sampleBundleJson,
    );

    expect(result.isValid, isFalse);
    expect(result.errors, isNotEmpty);
  });

  test('fails when the attestation is not a Sigstore bundle', () {
    final verifier = PubAttestationVerifier();

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: sampleArtifactBytes,
      bundleJson: '{"not": "a bundle"}',
    );

    expect(result.isValid, isFalse);
    expect(result.errors, isNotEmpty);
  });

  test('fails on an unsigned provenance statement', () {
    // `buildProvenanceBundleJson` produces a well-formed statement with a
    // bogus signature: the policy must never be reached.
    final verifier = PubAttestationVerifier();

    final result = verifier.verify(
      packageName: 'helpful',
      packageVersion: Version(1, 0, 0),
      archiveBytes: sampleArtifactBytes,
      bundleJson: buildProvenanceBundleJson(
        subjectName: 'helpful-1.0.0.tar.gz',
      ),
      expectedRepository: 'https://github.com/dieter/helpful',
    );

    expect(result.isValid, isFalse);
  });
}
