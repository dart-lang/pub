// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../sigstore/test_fixtures.dart';
import '../../test_pub.dart';

void main() {
  test('verifies a real signed package attestation and records provenance '
      '(helpful 0.1.5)', () async {
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
    expect(jsonDecode(packageProvenance.readAsStringSync()), {
      'repository': 'https://github.com/mosuem/helpful',
      'since': '0.1.5',
    });

    final lockfilePath = p.join(d.sandbox, appPath, 'pubspec.lock');
    expect(
      File(lockfilePath).readAsStringSync(),
      contains('provenance: "https://github.com/mosuem/helpful"'),
    );

    // An older unattested version stays installable: it predates the first
    // attested version, and `dart pub downgrade` must keep working.
    server.serve('helpful', '0.1.4');
    await pubDowngrade();
    expect(
      Directory(server.pathInCache('helpful', '0.1.4')).existsSync(),
      isTrue,
    );
    expect(
      File(lockfilePath).readAsStringSync(),
      isNot(contains('provenance')),
    );

    // A newer unattested version is rejected, even without a lockfile: an
    // attestation has been verified for 0.1.5 on this machine.
    File(lockfilePath).deleteSync();
    server.serve('helpful', '0.1.6');
    await pubGet(
      error: allOf(
        contains(
          'helpful 0.1.6 is not attested, but an attestation is '
          'expected',
        ),
        contains('versions from 0.1.5 on are expected to be attested'),
        contains(packageProvenance.path),
      ),
      exitCode: DATA,
    );
  });

  test(
    'expects the attestation that the lockfile records, on any machine',
    () async {
      final server = await servePackages();
      server.serve(
        'helpful',
        '0.1.5',
        slsaLevel: 2,
        archiveBytes: helpfulArchiveBytes,
        pubspec: {'repository': 'https://github.com/mosuem/helpful'},
      );
      const attestationPath =
          '/api/packages/helpful/versions/0.1.5/attestation';
      server.handle(attestationPath, (request) {
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
      final lockfilePath = p.join(d.sandbox, appPath, 'pubspec.lock');
      expect(
        File(lockfilePath).readAsStringSync(),
        contains('provenance: "https://github.com/mosuem/helpful"'),
      );

      // Another machine: nothing in the pub cache, the same lockfile. And the
      // repository no longer attests the version.
      Directory(
        server.pathInCache('helpful', '0.1.5'),
      ).deleteSync(recursive: true);
      Directory(server.provenanceCachingPath).deleteSync(recursive: true);
      server.serve(
        'helpful',
        '0.1.5',
        archiveBytes: helpfulArchiveBytes,
        pubspec: {'repository': 'https://github.com/mosuem/helpful'},
      );
      server.handle(attestationPath, (request) => Response.notFound('gone'));

      await pubGet(
        error: allOf(
          contains(
            'helpful 0.1.5 is not attested, but an attestation is '
            'expected',
          ),
          contains(
            'pubspec.lock records that helpful 0.1.5 was verified as '
            'built from https://github.com/mosuem/helpful',
          ),
          contains(
            'remove the `provenance` entry of helpful from pubspec.lock',
          ),
        ),
        exitCode: DATA,
      );

      // Dropping the expectation is an edit to the lockfile, visible in review.
      // The unverified download then records no provenance.
      final lockfile = File(lockfilePath);
      lockfile.writeAsStringSync(
        lockfile
            .readAsLinesSync()
            .where((line) => !line.trim().startsWith('provenance:'))
            .join('\n'),
      );
      await pubGet();
      expect(lockfile.readAsStringSync(), isNot(contains('provenance')));
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

  test('pub get fails with a clear message when the attestation endpoint '
      'fails', () async {
    // A failing attestation endpoint (or a proxy that does not forward it)
    // must be reported as such, not as a failure to find the package, and
    // must not re-download the archive on every attempt.
    final server = await servePackages();
    server.serve('foo', '1.0.0', slsaLevel: 2);
    server.handle('/api/packages/foo/versions/1.0.0/attestation', (request) {
      return Response.forbidden('nope');
    });

    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': server.url, 'version': '^1.0.0'},
          },
        )
        .create();

    await pubGet(
      error: allOf(
        contains('Failed to fetch the attestation of foo-1.0.0 from'),
        contains('/api/packages/foo/versions/1.0.0/attestation'),
        contains('proxy'),
      ),
      exitCode: TEMP_FAIL,
    );
    expect(
      server.requestedPaths.where((path) => path.endsWith('1.0.0.tar.gz')),
      hasLength(1),
    );
  });

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
      // The repository does not report `slsa_level` for this version, but an
      // attestation has been verified for an earlier version of the package
      // on this machine. A repository must not be able to turn verification
      // off.
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
      marker.writeAsStringSync(
        jsonEncode({
          'repository': 'https://github.com/dieter/helpful',
          'since': '0.9.0',
        }),
      );

      await pubGet(
        error: allOf(
          contains('foo 1.0.0 is not attested, but an attestation is expected'),
          contains('verified for foo 0.9.0 on this machine'),
          contains('delete `${marker.path}`'),
        ),
        exitCode: DATA,
      );

      // Versions before the first attested one are not expected to be
      // attested.
      marker.writeAsStringSync(
        jsonEncode({
          'repository': 'https://github.com/dieter/helpful',
          'since': '2.0.0',
        }),
      );
      await pubGet();
      expect(
        Directory(server.pathInCache('foo', '1.0.0')).existsSync(),
        isTrue,
      );
    },
  );

  test('ignores a malformed provenance record', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': server.url, 'version': '^1.0.0'},
          },
        )
        .create();
    final marker = File(p.join(server.provenanceCachingPath, 'foo.provenance'));
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync('https://github.com/dieter/helpful');

    await pubGet();
  });
}
