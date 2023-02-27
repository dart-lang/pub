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
    await appDir(dependencies: {'foo': 'any'}).create();
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
    await appDir(dependencies: {}).create();
    await pubGet(
      args: ['--enforce-lockfile'],
      error: '''
Retrieving dependencies failed.
Cannot do `--enforce-lockfile` without an existing `pubspec.lock`.

Try running `dart pub get` to create `pubspec.lock`.
''',
    );
  });

  test('Refuses to get in ./example if hash is updated', () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    server.serve('bar', '1.0.0');

    await appDir(dependencies: {'foo': '^1.0.0'}).create();
    await dir(appPath, [
      dir('example', [
        libPubspec(
          'example',
          '0.0.0',
          deps: {
            'bar': '1.0.0',
            'myapp': {'path': '../'}
          },
        )
      ])
    ]).create();
    await pubGet(args: ['--example']);

    server.serve(
      'bar',
      '1.0.0',
      contents: [
        file('README.md', 'Including this will change the content-hash.'),
      ],
    );
    // Deleting the version-listing cache will cause it to be refetched, and the
    // error will happen.
    File(p.join(globalServer.cachingPath, '.cache', 'bar-versions.json'))
        .deleteSync();

    final example = p.join('.', 'example');
    final examplePubspec = p.join('example', 'pubspec.yaml');
    final examplePubspecLock = p.join('example', 'pubspec.lock');

    await pubGet(
      args: ['--enforce-lockfile', '--example'],
      output: allOf(
        contains('Got dependencies!'),
        contains('Resolving dependencies in $example...'),
      ),
      error: allOf(
        contains(
          'Unable to satisfy `$examplePubspec` using `$examplePubspecLock` in $example.',
        ),
        contains(
            'To update `$examplePubspecLock` run `dart pub get` in $example without\n'
            '`--enforce-lockfile`.'),
      ),
      exitCode: DATA,
    );
  });

  test('Refuses to get if lockfile is missing package', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {}).create();
    await pubGet();
    await appDir(dependencies: {'foo': 'any'}).create();

    await pubGet(
      args: ['--enforce-lockfile'],
      output: allOf(
        contains('+ foo 1.0.0'),
        contains('Would have changed 1 dependency.'),
      ),
      error: contains('Unable to satisfy `pubspec.yaml` using `pubspec.lock`.'),
      exitCode: DATA,
    );
  });

  test('Refuses to get if package is locked to version not matching constraint',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');
    await appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();
    await appDir(dependencies: {'foo': '^2.0.0'}).create();
    await pubGet(
      args: ['--enforce-lockfile'],
      output: allOf([
        contains('> foo 2.0.0 (was 1.0.0)'),
        contains('Would have changed 1 dependency.'),
      ]),
      error: contains('Unable to satisfy `pubspec.yaml` using `pubspec.lock`.'),
      exitCode: DATA,
    );
  });

  test("Refuses to get if hash on server doesn't correspond to lockfile",
      () async {
    final server = await servePackages();
    server.serveContentHashes = true;
    server.serve('foo', '1.0.0');
    await appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        file('README.md', 'Including this will change the content-hash.'),
      ],
    );
    // Deleting the version-listing cache will cause it to be refetched, and the
    // error will happen.
    File(p.join(globalServer.cachingPath, '.cache', 'foo-versions.json'))
        .deleteSync();
    await pubGet(
      args: ['--enforce-lockfile'],
      output: allOf(
        contains('~ foo 1.0.0 (was 1.0.0)'),
        contains('Would have changed 1 dependency.'),
      ),
      error: allOf(
        contains('Cached version of foo-1.0.0 has wrong hash - redownloading.'),
        contains(
          'The existing content-hash from pubspec.lock doesn\'t match contents for:',
        ),
        contains(
          ' * foo-1.0.0 from "${server.url}"',
        ),
        contains(
          'Unable to satisfy `pubspec.yaml` using `pubspec.lock`.',
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
    await appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();
    await runPub(args: ['cache', 'clean', '-f']);
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        file('README.md', 'Including this will change the content-hash.'),
      ],
    );

    await pubGet(
      args: ['--enforce-lockfile'],
      output: allOf(
        contains('~ foo 1.0.0 (was 1.0.0)'),
        contains('Would have changed 1 dependency.'),
      ),
      error: allOf(
        contains('''
The existing content-hash from pubspec.lock doesn't match contents for:
 * foo-1.0.0 from "${server.url}"'''),
        contains('Unable to satisfy `pubspec.yaml` using `pubspec.lock`.'),
      ),
      exitCode: DATA,
    );
  });
}
