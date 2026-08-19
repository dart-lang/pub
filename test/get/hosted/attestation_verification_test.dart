// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub/src/exit_codes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  Map<String, dynamic> createTestBundleJson({
    required String archiveSha256,
    String packageName = 'foo',
    String packageVersion = '1.0.0',
    String repository = 'https://github.com/dart-lang/foo',
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

    final derBytes = <int>[
      0x30,
      0x82,
      0x01,
      0x00,
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

  test('verifies attestation during pub get if served by repository', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    final archiveSha = await server.peekArchiveSha256('foo', '1.0.0');
    final bundleJson = createTestBundleJson(archiveSha256: archiveSha);

    server.handle('/api/packages/foo/versions/1.0.0/attestation', (request) {
      return Response.ok(
        jsonEncode(bundleJson),
        headers: {'content-type': 'application/json; charset="utf-8"'},
      );
    });

    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': server.url, 'version': '^1.0.0'},
          },
        )
        .create();

    await pubGet();
    final cacheDir = server.pathInCache('foo', '1.0.0');
    expect(Directory(cacheDir).existsSync(), isTrue);
  });

  test(
    'pub get fails when attestation does not match package archive',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      // Tampered sha
      const fakeSha =
          '0000000000000000000000000000000000000000000000000000000000000000';
      final bundleJson = createTestBundleJson(archiveSha256: fakeSha);

      server.handle('/api/packages/foo/versions/1.0.0/attestation', (request) {
        return Response.ok(
          jsonEncode(bundleJson),
          headers: {'content-type': 'application/json; charset="utf-8"'},
        );
      });

      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': server.url, 'version': '^1.0.0'},
            },
          )
          .create();

      await pubGet(
        error: contains('failed Sigstore attestation verification'),
        exitCode: TEMP_FAIL,
      );
    },
  );
}
