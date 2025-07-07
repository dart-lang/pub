// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart';
import '../../test_pub.dart';

void main() {
  test(
    'activating a package from path gives error if package uses hooks',
    () async {
      final server = await servePackages();
      server.serve(
        'uses_hooks',
        '1.0.0',
        contents: [
          dir('hooks', [file('build.dart')]),
        ],
      );
      server.serve('uses_no_hooks', '1.0.0');

      await dir(appPath, [
        libPubspec(
          'foo',
          '1.2.3',
          extras: {
            'workspace': [
              'pkgs/foo_hooks',
              'pkgs/foo_dev_hooks',
              'pkgs/foo_no_hooks',
            ],
          },
          sdk: '^3.5.0',
        ),
        dir('pkgs', [
          dir('foo_hooks', [
            libPubspec(
              'foo_hooks',
              '1.1.1',
              deps: {'uses_hooks': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
          dir('foo_dev_hooks', [
            libPubspec(
              'foo_dev_hooks',
              '1.1.1',
              devDeps: {'uses_hooks': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
          dir('foo_no_hooks', [
            libPubspec(
              'foo_no_hooks',
              '1.1.1',
              deps: {'uses_no_hooks': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
        ]),
      ]).create();

      await runPub(
        args: ['global', 'activate', '-spath', p.join('pkgs', 'foo_hooks')],
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        error: '''
The dependency of foo_hooks, uses_hooks uses hooks.

You currently cannot `global activate` packages relying on hooks.

Follow progress in https://github.com/dart-lang/sdk/issues/60889.''',
        exitCode: 1,
      );

      await runPub(
        args: ['global', 'activate', '-spath', p.join('pkgs', 'foo_dev_hooks')],
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );

      await runPub(
        args: ['global', 'activate', '-spath', p.join('pkgs', 'foo_no_hooks')],
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      );
    },
  );

  test('activating a hosted package gives error if package uses hooks in direct'
      ' dependency', () async {
    final server = await servePackages();
    server.serve(
      'uses_hooks',
      '1.0.0',
      contents: [
        dir('hooks', [file('build.dart')]),
      ],
    );
    server.serve('foo_hooks', '1.1.1', deps: {'uses_hooks': '^1.0.0'});
    server.serve(
      'foo_hooks_in_dev_deps',
      '1.0.0',
      pubspec: {
        'dev_dependencies': {'uses_hooks': '^1.0.0'},
      },
    );

    await runPub(
      args: ['global', 'activate', 'uses_hooks'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: '''
Package uses_hooks uses hooks.

You currently cannot `global activate` packages relying on hooks.

Follow progress in https://github.com/dart-lang/sdk/issues/60889.''',
      exitCode: 1,
    );

    await runPub(
      args: ['global', 'activate', 'foo_hooks'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: '''
The dependency of foo_hooks, uses_hooks uses hooks.

You currently cannot `global activate` packages relying on hooks.

Follow progress in https://github.com/dart-lang/sdk/issues/60889.''',
      exitCode: 1,
    );

    await runPub(
      args: ['global', 'activate', 'foo_hooks_in_dev_deps'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });
}
