// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'descriptor.dart';
import 'test_pub.dart';

void main() {
  test('fetches dev_dependencies of workspace members', () async {
    final server = await servePackages();
    server.serve('dev_dep', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            devDeps: {'dev_dep': '^1.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: contains('+ dev_dep'),
    );
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(lockfile['packages'].keys, <String>{'dev_dep'});
    await appPackageConfigFile(
      [
        packageConfigEntry(name: 'dev_dep', version: '1.0.0'),
        packageConfigEntry(name: 'a', path: './pkgs/a'),
      ],
      generatorVersion: '3.7.0',
    ).validate();
  });

  test(
      'allows dependencies between workspace members, the source is overridden',
      () async {
    await servePackages();
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a', 'pkgs/b'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'b': '^2.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
        dir('b', [
          libPubspec(
            'b',
            '2.1.1',
            deps: {
              'myapp': {'git': 'somewhere'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'});
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(lockfile['packages'].keys, <String>{});
    await appPackageConfigFile(
      [
        packageConfigEntry(name: 'a', path: './pkgs/a'),
        packageConfigEntry(name: 'b', path: './pkgs/b'),
      ],
      generatorVersion: '3.7.0',
    ).validate();
  });

  test('allows nested workspaces', () async {
    final server = await servePackages();
    server.serve('dev_dep', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            extras: {
              'workspace': ['example'],
            },
            resolutionWorkspace: true,
          ),
          dir('example', [
            libPubspec(
              'example',
              '2.1.1',
              deps: {
                'a': {'path': '..'},
              },
              resolutionWorkspace: true,
            ),
          ]),
        ]),
      ]),
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'});
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(lockfile['packages'].keys, <String>{});

    await appPackageConfigFile(
      [
        packageConfigEntry(name: 'a', path: './pkgs/a'),
        packageConfigEntry(name: 'example', path: './pkgs/a/example'),
      ],
      generatorVersion: '3.7.0',
    ).validate();
  });

  test('checks constraints between workspace members', () async {
    await servePackages();
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'myapp': '^0.2.3'},
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      error: contains(
        'Because myapp depends on a which depends on myapp ^0.2.3, myapp ^0.2.3 is required',
      ),
    );
  });

  test(
      'ignores the source of dependencies on root packages. (Uses the local version instead)',
      () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {
              'myapp': {'posted': 'https://abc'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'});
  });

  test('Can resolve from any directory inside the workspace', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.7.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {
              'myapp': {'posted': 'https://abc'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      workingDirectory: p.join(sandbox, appPath, 'pkgs'),
      output: contains('Resolving dependencies in `..`...'),
    );
    final s = p.separator;
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      workingDirectory: p.join(sandbox, appPath, 'pkgs', 'a'),
      output: contains('Resolving dependencies in `..$s..`...'),
    );

    await pubGet(
      args: ['-C$appPath/pkgs'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      workingDirectory: sandbox,
      output: contains('Resolving dependencies in `$appPath`...'),
    );

    await pubGet(
      args: ['-C..'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      workingDirectory: p.join(
        sandbox,
        appPath,
        'pkgs',
      ),
      output: contains('Resolving dependencies in `..`...'),
    );
  });

  test('reports missing pubspec.yaml of workspace member correctly', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['a'],
        },
        sdk: '^3.7.0',
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          resolutionWorkspace: true,
          extras: {
            'workspace': ['b'], // Doesn't exist.
          },
        ),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      error: contains(
        'Could not find a file named "pubspec.yaml" in "${p.join(sandbox, appPath, 'a', 'b')}".\n'
        'That was included in the workspace of ${p.join('.', 'a', 'pubspec.yaml')}.\n'
        'That was included in the workspace of ${p.join('.', 'pubspec.yaml')}.',
      ),
      exitCode: NO_INPUT,
    );
  });
}
