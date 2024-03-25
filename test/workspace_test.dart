// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
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

  test('reports errors in workspace pubspec.yamls correctly', () async {
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

  test('`pub deps` lists dependencies for all members of workspace', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      deps: {'transitive': '^1.0.0'},
      contents: [
        dir('bin', [file('foomain.dart')]),
      ],
    );
    server.serve(
      'transitive',
      '1.0.0',
      contents: [
        dir('bin', [file('transitivemain.dart')]),
      ],
    );
    server.serve(
      'both',
      '1.0.0',
      contents: [
        dir('bin', [file('bothmain.dart')]),
      ],
    );

    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a', 'pkgs/b'],
        },
        deps: {'both': '^1.0.0', 'b': null},
        sdk: '^3.7.0',
      ),
      dir('bin', [file('myappmain.dart')]),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'myapp': null, 'foo': '^1.0.0'},
            devDeps: {'both': '^1.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
        dir('bin', [file('amain.dart')]),
        dir('b', [
          libPubspec(
            'b',
            '1.1.1',
            deps: {'myapp': null, 'both': '^1.0.0'},
            resolutionWorkspace: true,
          ),
          dir('bin', [file('bmain.dart')]),
        ]),
      ]),
    ]).create();
    await runPub(
      args: ['deps'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: contains(
        '''
Dart SDK 3.7.0
a 1.1.1
├── both...
├── foo 1.0.0
│   └── transitive 1.0.0
└── myapp...
b 1.1.1
├── both...
└── myapp...
myapp 1.2.3
├── b...
└── both 1.0.0''',
      ),
    );

    await runPub(
      args: ['deps', '--style=list', '--dev'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: '''
Dart SDK 3.7.0
myapp 1.2.3

dependencies:
- both 1.0.0
- b 1.1.1
  - myapp any
  - both ^1.0.0

b 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- both 1.0.0

a 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- foo 1.0.0
  - transitive ^1.0.0

dev dependencies:
- both 1.0.0

transitive dependencies:
- transitive 1.0.0''',
    );

    await runPub(
      args: ['deps', '--style=list', '--no-dev'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: '''
Dart SDK 3.7.0
myapp 1.2.3

dependencies:
- both 1.0.0
- b 1.1.1
  - myapp any
  - both ^1.0.0

b 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- both 1.0.0

a 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- foo 1.0.0
  - transitive ^1.0.0

transitive dependencies:
- transitive 1.0.0''',
    );
    await runPub(
      args: ['deps', '--style=compact'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: '''
    Dart SDK 3.7.0
myapp 1.2.3

dependencies:
- b 1.1.1 [myapp both]
- both 1.0.0

b 1.1.1

dependencies:
- both 1.0.0
- myapp 1.2.3 [both b]

a 1.1.1

dependencies:
- foo 1.0.0 [transitive]
- myapp 1.2.3 [both b]

dev dependencies:
- both 1.0.0

transitive dependencies:
- transitive 1.0.0''',
    );
    await runPub(
      args: ['deps', '--executables'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      output: '''
myapp:myappmain
both:bothmain
b:bmain
foo:foomain''',
    );
  });
}
