// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../descriptor.dart';
import '../test_pub.dart';

void main() {
  test('adds correct entries to cache and stores the content-hash', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');

    await appDir(dependencies: {'foo': '^2.0.0'}).create();
    // Do a `pub get` here to create a lock file in order to validate we later can
    // `pub get --offline` with packages installed by `preload`.
    await pubGet();

    await runPub(args: ['cache', 'clean', '-f']);

    final archivePath1 = p.join(sandbox, 'foo-1.0.0-archive.tar.gz');
    final archivePath2 = p.join(sandbox, 'foo-2.0.0-archive.tar.gz');

    File(archivePath1).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/1.0.0.tar.gz'),
      ),
    );
    File(archivePath2).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/2.0.0.tar.gz'),
      ),
    );
    await runPub(
      args: ['cache', 'preload', archivePath1, archivePath2],
      environment: {'_PUB_TEST_DEFAULT_HOSTED_URL': server.url},
      output: allOf(
        [
          contains('Installed $archivePath1 in cache as foo 1.0.0.'),
          contains('Installed $archivePath2 in cache as foo 2.0.0.'),
        ],
      ),
    );
    await d.cacheDir({'foo': '1.0.0'}).validate();
    await d.cacheDir({'foo': '2.0.0'}).validate();

    await hostedHashesCache([
      file('foo-1.0.0.sha256', await server.peekArchiveSha256('foo', '1.0.0')),
    ]).validate();

    await hostedHashesCache([
      file('foo-2.0.0.sha256', await server.peekArchiveSha256('foo', '2.0.0')),
    ]).validate();

    await pubGet(args: ['--offline']);
  });

  test(
      'installs package according to PUB_HOSTED_URL even on non-offical server',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    final archivePath = p.join(sandbox, 'archive');

    File(archivePath).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/1.0.0.tar.gz'),
      ),
    );
    await runPub(
      args: ['cache', 'preload', archivePath],
      // By having pub.dev be the "official" server the test-server (localhost)
      // is considered non-official. Test that the output mentions that we
      // are installing to a non-official server.
      environment: {'_PUB_TEST_DEFAULT_HOSTED_URL': 'pub.dev'},
      output: allOf([
        contains(
          'Installed $archivePath in cache as foo 1.0.0 from ${server.url}.',
        )
      ]),
    );
    await d.cacheDir({'foo': '1.0.0'}).validate();
  });

  test('overwrites existing entry in cache', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', contents: [file('old-file.txt')]);

    final archivePath = p.join(sandbox, 'archive');

    File(archivePath).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/1.0.0.tar.gz'),
      ),
    );
    await runPub(
      args: ['cache', 'preload', archivePath],
      environment: {'_PUB_TEST_DEFAULT_HOSTED_URL': server.url},
      output:
          allOf([contains('Installed $archivePath in cache as foo 1.0.0.')]),
    );

    server.serve('foo', '1.0.0', contents: [file('new-file.txt')]);

    File(archivePath).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/1.0.0.tar.gz'),
      ),
    );

    File(archivePath).writeAsBytesSync(
      await readBytes(
        Uri.parse(server.url).resolve('packages/foo/versions/1.0.0.tar.gz'),
      ),
    );

    await runPub(
      args: ['cache', 'preload', archivePath],
      environment: {'_PUB_TEST_DEFAULT_HOSTED_URL': server.url},
      output:
          allOf([contains('Installed $archivePath in cache as foo 1.0.0.')]),
    );
    await hostedCache([
      dir('foo-1.0.0', [file('new-file.txt'), nothing('old-file.txt')])
    ]).validate();
  });

  test('handles missing archive', () async {
    final archivePath = p.join(sandbox, 'archive');
    await runPub(
      args: ['cache', 'preload', archivePath],
      error: contains('Could not find file $archivePath.'),
      exitCode: 1,
    );
  });

  test('handles broken archives', () async {
    final archivePath = p.join(sandbox, 'archive');
    File(archivePath).writeAsBytesSync('garbage'.codeUnits);
    await runPub(
      args: ['cache', 'preload', archivePath],
      error:
          contains('Failed to extract `$archivePath`: Filter error, bad data.'),
      exitCode: DATA,
    );
  });

  test('handles missing pubspec.yaml in archive', () async {
    final archivePath = p.join(sandbox, 'archive');

    // Create a tar.gz with a single file (and no pubspec.yaml).
    File(archivePath).writeAsBytesSync(
      await tarFromDescriptors([d.file('foo.txt')]).expand((x) => x).toList(),
    );

    await runPub(
      args: ['cache', 'preload', archivePath],
      error: contains(
        'Found no `pubspec.yaml` in $archivePath. Is it a valid pub package archive?',
      ),
      exitCode: 1,
    );
  });

  test('handles broken pubspec.yaml in archive', () async {
    final archivePath = p.join(sandbox, 'archive');

    File(archivePath).writeAsBytesSync(
      await tarFromDescriptors([d.file('pubspec.yaml', '{}')])
          .expand((x) => x)
          .toList(),
    );

    await runPub(
      args: ['cache', 'preload', archivePath],
      error: contains(
        'Failed to load `pubspec.yaml` from `$archivePath`: Error on line 1, column 1',
      ),
      exitCode: 1,
    );
  });
}
