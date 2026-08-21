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
  test('successfully verifies valid package and attestation', () {
    final verifier = PubAttestationVerifier();
    final bundle = SigstoreBundle.fromJson(sampleBundleJson);

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: sampleArtifactBytes,
      bundle: bundle,
      expectedRepository:
          'https://github.com/sigstore-conformance/extremely-dangerous-public-oidc-beacon',
    );

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(result.packageName, equals('sample'));
    expect(
      result.repository,
      equals(
        'https://github.com/sigstore-conformance/extremely-dangerous-public-oidc-beacon',
      ),
    );
  });

  test('fails when archive bytes do not match attestation', () {
    final verifier = PubAttestationVerifier();
    final bundle = SigstoreBundle.fromJson(sampleBundleJson);

    final tamperedBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: tamperedBytes,
      bundle: bundle,
    );

    expect(result.isValid, isFalse);
    expect(result.errors, isNotEmpty);
  });

  test('fails when repository does not match expected repository', () {
    final verifier = PubAttestationVerifier();
    final bundle = SigstoreBundle.fromJson(sampleBundleJson);

    final result = verifier.verify(
      packageName: 'sample',
      packageVersion: Version(1, 0, 0),
      archiveBytes: sampleArtifactBytes,
      bundle: bundle,
      expectedRepository: 'https://github.com/unexpected-owner/unexpected-repo',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.first, contains('does not match expected repository'));
  });
}
