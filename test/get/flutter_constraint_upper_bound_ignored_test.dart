// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
    'pub get succeeds despite of "invalid" flutter upper bound in dependency',
    () async {
      final fakeFlutterRoot = d.dir('fake_flutter_root', [
        d.flutterVersion('1.23.0'),
      ]);
      await fakeFlutterRoot.create();

      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '^$testVersion', 'flutter': '>=0.5.0 <1.0.0'},
        },
      );

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet(
        exitCode: exit_codes.SUCCESS,
        environment: {'FLUTTER_ROOT': fakeFlutterRoot.io.path},
      );
    },
  );

  test('pub get ignores the bound of the root package before 3.10', () async {
    final fakeFlutterRoot = d.dir('fake_flutter_root', [
      d.flutterVersion('1.23.0'),
    ]);
    await fakeFlutterRoot.create();

    await d
        .appDir(
          pubspec: {
            'environment': {'sdk': '^3.8.0', 'flutter': '>=0.5.0 <1.0.0'},
          },
        )
        .create();

    await pubGet(
      environment: {
        'FLUTTER_ROOT': fakeFlutterRoot.io.path,
        '_PUB_TEST_SDK_VERSION': '3.9.0',
      },
    );
  });

  test('pub get respects the bound of the root package after 3.9', () async {
    final fakeFlutterRoot = d.dir('fake_flutter_root', [
      d.flutterVersion('1.23.0'),
    ]);
    await fakeFlutterRoot.create();

    await d
        .appDir(
          pubspec: {
            'environment': {'sdk': '^3.9.0', 'flutter': '>=0.5.0 <1.0.0'},
          },
        )
        .create();

    await pubGet(
      exitCode: 1,
      environment: {
        'FLUTTER_ROOT': fakeFlutterRoot.io.path,
        '_PUB_TEST_SDK_VERSION': '3.9.0',
      },
      error: contains(
        'Because myapp requires '
        'Flutter SDK version >=0.5.0 <1.0.0, version solving failed',
      ),
    );
  });

  test('pub get respects the bound of a workspace root package', () async {
    final fakeFlutterRoot = d.dir('fake_flutter_root', [
      d.flutterVersion('1.23.0'),
    ]);
    await fakeFlutterRoot.create();

    await d.dir(appPath, [
      d.appPubspec(
        extras: {
          'environment': {'sdk': '^3.9.0'},
          'workspace': ['app'],
        },
      ),
      d.dir('app', [
        d.libPubspec(
          'app',
          '1.0.0',
          resolutionWorkspace: true,
          extras: {
            'environment': {'sdk': '^3.9.0', 'flutter': '>=0.5.0 <1.0.0'},
          },
        ),
      ]),
    ]).create();

    await pubGet(
      exitCode: 1,
      environment: {
        '_PUB_TEST_SDK_VERSION': '3.9.0',
        'FLUTTER_ROOT': fakeFlutterRoot.io.path,
      },
      error: contains(
        'Because app requires '
        'Flutter SDK version >=0.5.0 <1.0.0, version solving failed',
      ),
    );
  });
}
