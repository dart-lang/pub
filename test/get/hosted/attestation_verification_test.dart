// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../sigstore/test_fixtures.dart';
import '../../test_pub.dart';

void main() {
  test(
    'verifies a real signed package attestation and records provenance (helpful 0.1.5)',
    () async {
      final server = await servePackages();
      server.serve(
        'helpful',
        '0.1.5',
        slsaLevel: 2,
        archiveBytes: helpfulArchiveBytes,
        pubspec: {'repository': 'https://github.com/mosuem/helpful'},
      );
      server.handle('/api/packages/helpful/versions/0.1.5/attestation', (
        request,
      ) {
        return Response.ok(
          helpfulBundleJson,
          headers: {'content-type': 'application/json; charset="utf-8"'},
        );
      });

      await d
          .appDir(
            dependencies: {
              'helpful': {'hosted': server.url, 'version': '^0.1.0'},
            },
          )
          .create();

      await pubGet();

      final cacheDir = server.pathInCache('helpful', '0.1.5');
      expect(Directory(cacheDir).existsSync(), isTrue);

      final versionProvenance = File(
        p.join(server.provenanceCachingPath, 'helpful-0.1.5.provenance'),
      );
      final packageProvenance = File(
        p.join(server.provenanceCachingPath, 'helpful.provenance'),
      );
      expect(
        versionProvenance.readAsStringSync(),
        'https://github.com/mosuem/helpful',
      );
      expect(
        packageProvenance.readAsStringSync(),
        'https://github.com/mosuem/helpful',
      );

      final lockfile =
          File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
      expect(
        lockfile,
        contains('provenance: "https://github.com/mosuem/helpful"'),
      );

      // Serving a newer unattested version of the same package must be
      // rejected as a downgrade even if the lockfile is deleted.
      File(p.join(d.sandbox, appPath, 'pubspec.lock')).deleteSync();
      server.serve('helpful', '0.1.6');
      await pubGet(
        error: contains('Downgrading from a signed package'),
        exitCode: DATA,
      );
    },
  );

  test('proceeds when no attestation is served by repository', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

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
      server.serve('foo', '1.0.0', slsaLevel: 2);

      server.handle('/api/packages/foo/versions/1.0.0/attestation', (request) {
        return Response.ok(
          sampleBundleJson,
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

  test('pub get fails when an attestation is claimed but not served', () async {
    // Reporting `slsa_level` and then not serving an attestation must not
    // silently downgrade to an unverified install.
    final server = await servePackages();
    server.serve('foo', '1.0.0', slsaLevel: 2);

    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': server.url, 'version': '^1.0.0'},
          },
        )
        .create();

    await pubGet(error: contains('served no attestation'), exitCode: TEMP_FAIL);
  });

  test(
    'pub get fails when a previously attested package is no longer attested',
    () async {
      // The repository does not report `slsa_level` for this version, but we
      // have seen an attestation for this package before. A repository must
      // not be able to turn verification off.
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': server.url, 'version': '^1.0.0'},
            },
          )
          .create();

      final marker = File(
        p.join(server.provenanceCachingPath, 'foo.provenance'),
      );
      marker.parent.createSync(recursive: true);
      marker.writeAsStringSync('https://github.com/dieter/helpful');

      await pubGet(
        error: contains('Downgrading from a signed package'),
        exitCode: DATA,
      );
    },
  );
}
