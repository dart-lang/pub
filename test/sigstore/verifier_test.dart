// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pub/src/sigstore/models.dart';
import 'package:pub/src/sigstore/verifier.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  final mockTrustedRoot = {
    'mediaType': 'application/vnd.dev.sigstore.trustedroot+json;version=0.1',
    'certificateAuthorities': [
      {
        'subject': {'organization': 'sigstore.dev', 'commonName': 'fulcio'},
        'uri': 'https://fulcio.sigstore.dev',
      },
    ],
    'tlogs': [
      {
        'baseUrl': 'https://rekor.sigstore.dev',
        'logId': {'keyId': 'test-rekor-key-id'},
      },
    ],
  };

  Map<String, dynamic> createTestBundleJson({
    required String archiveSha256,
    String packageName = 'helpful',
    String packageVersion = '0.1.4',
    String repository = 'https://github.com/mosuem/helpful',
    String issuer = 'https://token.actions.githubusercontent.com',
  }) {
    final statement = {
      '_type': 'https://in-toto.io/Statement/v1',
      'subject': [
        {
          'name': '$packageName-$packageVersion.tar.gz',
          'digest': {'sha256': archiveSha256},
        },
      ],
      'predicateType': 'https://slsa.dev/provenance/v1',
      'predicate': {
        'buildDefinition': {
          'buildType': 'https://actions.github.io/buildtypes/workflow/v1',
          'externalParameters': {
            'workflow': {
              'ref': 'refs/tags/v$packageVersion',
              'repository': repository,
              'path': '.github/workflows/publish.yaml',
            },
          },
          'resolvedDependencies': [
            {
              'uri': 'git+$repository@refs/tags/v$packageVersion',
              'digest': {
                'gitCommit': '7891abbe3dab159e9d0187fc1042d5e0cd82cfad',
              },
            },
          ],
        },
        'runDetails': {
          'builder': {
            'id':
                'https://github.com/dart-lang/ecosystem/.github/workflows/publish.yaml@refs/heads/main',
          },
        },
      },
    };

    final payloadBase64 = base64Encode(utf8.encode(jsonEncode(statement)));

    // Create minimal mock DER with embedded UTF-8 string markers for OIDs
    final derBytes = <int>[
      0x30, 0x82, 0x01, 0x00, // SEQUENCE
      ...utf8.encode(repository),
      ...utf8.encode(issuer),
    ];

    return {
      'mediaType': 'application/vnd.dev.sigstore.bundle.v0.3+json',
      'verificationMaterial': {
        'certificate': {'rawBytes': base64Encode(derBytes)},
        'tlogEntries': [
          {
            'logIndex': '123456',
            'inclusionProof': {
              'rootHash': 'test-root-hash',
              'hashes': ['hash1', 'hash2'],
            },
          },
        ],
      },
      'dsseEnvelope': {
        'payloadType': 'application/vnd.in-toto+json',
        'payload': payloadBase64,
        'signatures': [
          {'sig': base64Encode(utf8.encode('test-signature'))},
        ],
      },
    };
  }

  test('successfully verifies valid package and attestation', () {
    final archiveBytes = Uint8List.fromList(
      utf8.encode('fake-archive-bytes-0.1.4'),
    );
    final archiveSha = sha256.convert(archiveBytes).toString();

    final bundleJson = createTestBundleJson(archiveSha256: archiveSha);
    final bundle = SigstoreBundle.fromJson(bundleJson);

    final verifier = AttestationVerifier(trustedRoot: mockTrustedRoot);
    final result = verifier.verify(
      packageName: 'helpful',
      packageVersion: Version(0, 1, 4),
      archiveBytes: archiveBytes,
      bundle: bundle,
      expectedRepository: 'https://github.com/mosuem/helpful',
      pubspecRepository: 'https://github.com/mosuem/helpful',
    );

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(result.packageName, equals('helpful'));
    expect(result.repository, equals('https://github.com/mosuem/helpful'));
  });

  test('fails when archive sha256 does not match attestation', () {
    final archiveBytes = Uint8List.fromList(
      utf8.encode('tampered-archive-bytes'),
    );
    const originalSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    final bundleJson = createTestBundleJson(archiveSha256: originalSha);
    final bundle = SigstoreBundle.fromJson(bundleJson);

    final verifier = AttestationVerifier(trustedRoot: mockTrustedRoot);
    final result = verifier.verify(
      packageName: 'helpful',
      packageVersion: Version(0, 1, 4),
      archiveBytes: archiveBytes,
      bundle: bundle,
    );

    expect(result.isValid, isFalse);
    expect(result.errors.any((e) => e.contains('SHA-256')), isTrue);
  });

  test('fails when repository does not match pubspec.yaml', () {
    final archiveBytes = Uint8List.fromList(utf8.encode('valid-archive-bytes'));
    final archiveSha = sha256.convert(archiveBytes).toString();

    final bundleJson = createTestBundleJson(
      archiveSha256: archiveSha,
      repository: 'https://github.com/attacker/helpful',
    );
    final bundle = SigstoreBundle.fromJson(bundleJson);

    final verifier = AttestationVerifier(trustedRoot: mockTrustedRoot);
    final result = verifier.verify(
      packageName: 'helpful',
      packageVersion: Version(0, 1, 4),
      archiveBytes: archiveBytes,
      bundle: bundle,
      pubspecRepository: 'https://github.com/legitimate-owner/helpful',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.any((e) => e.contains('pubspec.yaml')), isTrue);
  });
}
