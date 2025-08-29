// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Will short-cut if resolution is up-to-date', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('foo', '2.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet(args: ['--check-up-to-date'], output: contains('+ foo 1.0.0'));

    await pubGet(
      args: ['--check-up-to-date'],
      output: contains('Resolution is up-to-date'),
    );

    // Wait for timestamps to align.
    await Future<Null>.delayed(const Duration(seconds: 1));

    await d.appDir(dependencies: {'foo': '2.0.0'}).create();

    await pubGet(args: ['--check-up-to-date'], output: contains('> foo 2.0.0'));
  });

  test('--dry-run will exit non-zero if there are changes', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      error: contains('Resolution needs updating. Run `dart pub get`'),

      exitCode: 1,
    );

    await d.dir(appPath, [
      d.nothing('pubspec.lock'),
      d.nothing('.dart_tool/package_config.json'),
    ]).validate();

    await pubGet();

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      output: contains('Resolution is up-to-date'),
      exitCode: 0,
    );

    await d.appDir(dependencies: {'foo': '2.0.0'}).create();

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      error: contains('Resolution needs updating. Run `dart pub get`'),
      exitCode: 1,
    );
  });

  test('Works in a workspace', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.0.0',
        sdk: '^3.5.0',
        deps: {'foo': '1.0.0'},
        extras: {
          'workspace': ['pkg'],
        },
      ),
      d.dir('pkg', [d.libPubspec('pkg', '1.0.0', resolutionWorkspace: true)]),
    ]).create();

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      error: contains('Resolution needs updating. Run `dart pub get`'),
      exitCode: 1,
    );

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      output: contains('+ foo 1.0.0'),
    );

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      output: contains('Resolution is up-to-date'),
      exitCode: 0,
    );

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.0.0',
        sdk: '^3.5.0',
        deps: {'foo': '1.0.0'},
        extras: {
          'workspace': ['pkg'],
        },
      ),
    ]).create();

    await pubGet(
      args: ['--check-up-to-date', '--dry-run'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      error: contains('Resolution needs updating. Run `dart pub get`'),
      exitCode: 1,
    );
  });
}
