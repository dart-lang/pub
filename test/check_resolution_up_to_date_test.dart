// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('Will exit non-zero if there are changes', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await runPub(
      args: ['check-resolution-up-to-date'],
      error: contains('Resolution needs updating. Run `dart pub get`'),

      exitCode: 1,
    );

    await d.dir(appPath, [
      d.nothing('pubspec.lock'),
      d.nothing('.dart_tool/package_config.json'),
    ]).validate();

    await pubGet();

    await runPub(
      args: ['check-resolution-up-to-date'],
      output: contains('Resolution is up-to-date'),
      exitCode: 0,
    );

    // Timestamp resolution is rather poor especially on windows.
    await Future<Null>.delayed(const Duration(seconds: 1));

    await d.appDir(dependencies: {'foo': '2.0.0'}).create();

    await runPub(
      args: ['check-resolution-up-to-date'],
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

    await runPub(
      args: ['check-resolution-up-to-date'],
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

    await runPub(
      args: ['check-resolution-up-to-date'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      output: contains('Resolution is up-to-date'),
      exitCode: 0,
    );

    // Timestamp resolution is rather poor especially on windows.
    await Future<Null>.delayed(const Duration(seconds: 1));

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

    await runPub(
      args: ['check-resolution-up-to-date'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(d.sandbox, appPath, 'pkg'),
      error: contains('Resolution needs updating. Run `dart pub get`'),
      exitCode: 1,
    );
  });
}
