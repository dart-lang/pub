// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart';
import '../test_pub.dart';

Future<void> main() async {
  test('Recreates .dart_tool/package_config.json, redownloads archives',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await appDir({'foo': 'any'}).create();
    await pubGet();
    final packageConfig =
        File(path(p.join(appPath, '.dart_tool', 'package_config.json')));
    packageConfig.deleteSync();
    await runPub(args: ['cache', 'clean', '-f']);
    await pubGet(args: ['--enforce-lockfile']);
    expect(packageConfig.existsSync(), isTrue);
    await cacheDir({'foo': '1.0.0'}).validate();
    await appPackageConfigFile([
      packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();
  });

  test('Refuses to get if no lockfile exists', () async {
    await appDir({}).create();
    await pubGet(
      args: ['--enforce-lockfile'],
      error:
          'Retrieving dependencies failed. Cannot do `--enforce-lockfile` without an existing `pubspec.lock`.',
    );
  });

  test('Refuses to get if lockfile is missing package', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await appDir({}).create();
    await pubGet();
    await appDir({'foo': 'any'}).create();

    await pubGet(
      args: ['--enforce-lockfile'],
      output: '+ foo 1.0.0',
      error: 'Could not enforce the lockfile.',
      exitCode: DATA,
    );
  });

  test('Refuses to get if package is locked to version not matching constraint',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');
    await appDir({'foo': '^1.0.0'}).create();
    await pubGet();
    await appDir({'foo': '^2.0.0'}).create();
    await pubGet(
      args: ['--enforce-lockfile'],
      output: contains('> foo 2.0.0 (was 1.0.0)'),
      error: contains('Could not enforce the lockfile.'),
      exitCode: DATA,
    );
  });

  test("Refuses to get if hash on server doesn't correspond to lockfile",
      () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir({'foo': '^1.0.0'}).create();
    await pubGet();
    server.serve('foo', '1.0.0', contents: [
      file('README.md', 'Including this will change the content-hash.'),
    ]);
    // Deleting the version-listing cache will cause it to be refetched, and the
    // error will happen.
    File(p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'))
        .deleteSync();
    await pubGet(
      args: ['--enforce-lockfile'],
      error: allOf(
        contains('Cached version of foo-1.0.0 has wrong hash - redownloading.'),
        contains(
          'The existing content-hash from pubspec.lock doesn\'t match contents for:',
        ),
        contains(
          ' * foo-1.0.0 from "${server.url}"',
        ),
        contains(
          'Could not enforce the lockfile.',
        ),
      ),
      exitCode: DATA,
    );
  });

  test(
      'Refuses to get if archive on legacy server doesn\'t have hash corresponding to lockfile',
      () async {
    final server = await servePackages();
    server.serveContentHashes = false;
    server.serve('foo', '1.0.0');
    await appDir({'foo': '^1.0.0'}).create();
    await pubGet();
    await runPub(args: ['cache', 'clean', '-f']);
    server.serve('foo', '1.0.0', contents: [
      file('README.md', 'Including this will change the content-hash.'),
    ]);

    await pubGet(
      args: ['--enforce-lockfile'],
      error: contains('''
The existing content-hash from pubspec.lock doesn't match contents for:
 * foo-1.0.0 from "${server.url}"'''),
      exitCode: DATA,
    );
  });
}
