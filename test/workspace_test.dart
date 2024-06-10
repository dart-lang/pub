// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'descriptor.dart';
import 'lish/utils.dart';
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
        sdk: '^3.5.0',
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
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
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
      generatorVersion: '3.5.0',
    ).validate();
    final workspaceRefA = jsonDecode(
      File(
        p.join(
          sandbox,
          appPath,
          'pkgs',
          'a',
          '.dart_tool',
          'pub',
          'workspace_ref.json',
        ),
      ).readAsStringSync(),
    );
    expect(workspaceRefA, {'workspaceRoot': p.join('..', '..', '..', '..')});
    final workspaceRefMyApp = jsonDecode(
      File(p.join(sandbox, appPath, '.dart_tool', 'pub', 'workspace_ref.json'))
          .readAsStringSync(),
    );
    expect(workspaceRefMyApp, {'workspaceRoot': p.join('..', '..')});
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
        sdk: '^3.5.0',
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
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(lockfile['packages'].keys, <String>{});
    await appPackageConfigFile(
      [
        packageConfigEntry(name: 'a', path: './pkgs/a'),
        packageConfigEntry(name: 'b', path: './pkgs/b'),
      ],
      generatorVersion: '3.5.0',
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
        sdk: '^3.5.0',
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
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    final lockfile = loadYaml(
      File(p.join(sandbox, appPath, 'pubspec.lock')).readAsStringSync(),
    );
    expect(lockfile['packages'].keys, <String>{});

    await appPackageConfigFile(
      [
        packageConfigEntry(name: 'a', path: './pkgs/a'),
        packageConfigEntry(name: 'example', path: './pkgs/a/example'),
      ],
      generatorVersion: '3.5.0',
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
        sdk: '^3.5.0',
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
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
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
        sdk: '^3.5.0',
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
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
  });

  test('reports errors in workspace pubspec.yamls correctly', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {
              'foo': [1, 2, 3],
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    final s = p.separator;
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains(
        'Error on line 1, column 118 of pkgs${s}a${s}pubspec.yaml: A dependency specification must be a string or a mapping.',
      ),
      exitCode: DATA,
    );
  });

  test('reports solve failures in workspace pubspec.yamls correctly', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {
              'foo': {'posted': 'https://abc'},
            },
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains(
        'Because a depends on foo from unknown source "posted", version solving failed.',
      ),
    );
  });

  test('Rejects workspace pubspecs without "resolution: workspace"', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
          ),
        ]),
      ]),
    ]).create();
    final s = p.separator;
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains(
        'pkgs${s}a${s}pubspec.yaml is included in the workspace from .${s}pubspec.yaml, but does not have `resolution: workspace`.',
      ),
    );
  });

  test('Can resolve from any directory inside the workspace', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
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
    final absoluteAppPath = p.join(sandbox, appPath);
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(sandbox, appPath, 'pkgs'),
      output: allOf(
        contains(
          'Resolving dependencies in `$absoluteAppPath`...',
        ),
        contains('Got dependencies in `$absoluteAppPath`'),
      ),
    );
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(sandbox, appPath, 'pkgs', 'a'),
      output: contains(
        'Resolving dependencies in `${p.join(sandbox, appPath)}`...',
      ),
    );

    await pubGet(
      args: ['-C$appPath/pkgs'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: sandbox,
      output: contains('Resolving dependencies in `$appPath`...'),
    );

    await pubGet(
      args: ['-C..'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      workingDirectory: p.join(
        sandbox,
        appPath,
        'pkgs',
      ),
      output: contains(
        'Resolving dependencies in `${p.join(sandbox, appPath)}`...',
      ),
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
        sdk: '^3.5.0',
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
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains(
        'Could not find a file named "pubspec.yaml" in "${p.join(sandbox, appPath, 'a', 'b')}".\n'
        'That was included in the workspace of ${p.join('.', 'a', 'pubspec.yaml')}.\n'
        'That was included in the workspace of ${p.join('.', 'pubspec.yaml')}.',
      ),
      exitCode: NO_INPUT,
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
        sdk: '^3.5.0',
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
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
Dart SDK 3.5.0
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
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: '''
Dart SDK 3.5.0
myapp 1.2.3

dependencies:
- both 1.0.0
- b 1.1.1
  - myapp any
  - both ^1.0.0

a 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- foo 1.0.0
  - transitive ^1.0.0

dev dependencies:
- both 1.0.0

b 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- both 1.0.0

transitive dependencies:
- transitive 1.0.0''',
    );

    await runPub(
      args: ['deps', '--style=list', '--no-dev'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: '''
Dart SDK 3.5.0
myapp 1.2.3

dependencies:
- both 1.0.0
- b 1.1.1
  - myapp any
  - both ^1.0.0

a 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- foo 1.0.0
  - transitive ^1.0.0

b 1.1.1

dependencies:
- myapp 1.2.3
  - both ^1.0.0
  - b any
- both 1.0.0

transitive dependencies:
- transitive 1.0.0''',
    );
    await runPub(
      args: ['deps', '--style=compact'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: '''
    Dart SDK 3.5.0
myapp 1.2.3

dependencies:
- b 1.1.1 [myapp both]
- both 1.0.0

a 1.1.1

dependencies:
- foo 1.0.0 [transitive]
- myapp 1.2.3 [both b]

dev dependencies:
- both 1.0.0

b 1.1.1

dependencies:
- both 1.0.0
- myapp 1.2.3 [both b]

transitive dependencies:
- transitive 1.0.0''',
    );
    await runPub(
      args: ['deps', '--executables'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: '''
myapp:myappmain
both:bothmain
b:bmain
foo:foomain''',
    );
  });

  test('`pub add` acts on the work package', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', sdk: '^3.5.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    final aDir = p.join(sandbox, appPath, 'pkgs', 'a');
    await pubAdd(
      args: ['foo'],
      output: contains('+ foo 1.0.0'),
      workingDirectory: aDir,
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
    await dir(appPath, [
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'foo': '^1.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).validate();
  });

  test('`pub remove` acts on the work package', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', sdk: '^3.5.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        deps: {'foo': '^1.0.0'},
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            deps: {'foo': '^1.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    final aDir = p.join(sandbox, appPath, 'pkgs', 'a');
    await pubRemove(
      args: ['foo'],
      output: isNot(contains('- foo 1.0.0')),
      workingDirectory: aDir,
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
    await dir(appPath, [
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.1.1',
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).validate();
    // Only when removing it from the root it shows the update.
    await pubRemove(
      args: ['foo'],
      output: contains('- foo 1.0.0'),
      workingDirectory: path(appPath),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });

  test('Removes lock files and package configs from workspace members',
      () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir(
          'a',
          [
            libPubspec('a', '1.1.1', resolutionWorkspace: true),
          ],
        ),
      ]),
    ]).create();
    final aDir = p.join(sandbox, appPath, 'pkgs', 'a');
    final pkgsDir = p.join(sandbox, appPath, 'pkgs');
    final strayLockFile = File(p.join(aDir, 'pubspec.lock'));
    final strayPackageConfig =
        File(p.join(aDir, '.dart_tool', 'package_config.json'));

    final unmanagedLockFile = File(p.join(pkgsDir, 'pubspec.lock'));
    final unmanagedPackageConfig =
        File(p.join(pkgsDir, '.dart_tool', 'package_config.json'));
    strayPackageConfig.createSync(recursive: true);
    strayLockFile.createSync(recursive: true);

    unmanagedPackageConfig.createSync(recursive: true);
    unmanagedLockFile.createSync(recursive: true);

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});

    expect(strayLockFile.statSync().type, FileSystemEntityType.notFound);
    expect(strayPackageConfig.statSync().type, FileSystemEntityType.notFound);

    // We only delete stray files from directories that contain an actual
    // package.
    expect(unmanagedLockFile.statSync().type, FileSystemEntityType.file);
    expect(unmanagedPackageConfig.statSync().type, FileSystemEntityType.file);
  });

  test('Reports error if workspace doesn\'t form a tree.', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['pkgs/a', 'pkgs'],
        },
      ),
      dir('pkgs', [
        libPubspec(
          'a',
          '1.1.1',
          resolutionWorkspace: true,
          extras: {
            'workspace': ['a'],
          },
        ),
        dir(
          'a',
          [
            libPubspec('a', '1.1.1', resolutionWorkspace: true),
          ],
        ),
      ]),
    ]).create();
    final s = p.separator;
    await pubGet(
      error: '''
Packages can only be included in the workspace once.

`.${s}pkgs${s}a${s}pubspec.yaml` is included in the workspace, both from:
* `.${s}pkgs${s}pubspec.yaml` and
* .${s}pubspec.yaml.''',
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });

  test(
      'Reports a failure if a workspace pubspec is not nested inside the parent dir',
      () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['../'],
        },
      ),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains('"workspace" members must be subdirectories'),
      exitCode: DATA,
    );
  });

  test('Reports a failure if a workspace includes "."', () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        sdk: '^3.5.0',
        extras: {
          'workspace': ['.'],
        },
      ),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains('"workspace" members must be subdirectories'),
      exitCode: DATA,
    );
  });

  test('Reports a failure if a workspace pubspec is not a relative path',
      () async {
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        sdk: '^3.5.0',
        extras: {
          'workspace': [p.join(sandbox, appPath, 'a')],
        },
      ),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains('"workspace" members must be relative paths'),
      exitCode: DATA,
    );
  });

  test('`upgrade` upgrades all workspace', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('bar', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'bar': '^1.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    server.serve('foo', '1.5.0');
    server.serve('bar', '1.5.0');
    await pubUpgrade(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
> bar 1.5.0 (was 1.0.0)
> foo 1.5.0 (was 1.0.0)''',
      ),
    );
  });

  test('`upgrade --major-versions` upgrades all workspace', () async {
    final server = await servePackages();
    server.serve('foo', '1.5.0');
    server.serve('foo', '2.0.0');
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.0.0', 'bar': '1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '1.5.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('+ foo 1.5.0'),
    );
    await pubUpgrade(
      args: ['--major-versions'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
Changed 2 constraints in pubspec.yaml:
  foo: ^1.0.0 -> ^2.0.0
  bar: 1.0.0 -> ^2.0.0

Changed 1 constraint in a${s}pubspec.yaml:
  foo: 1.5.0 -> ^2.0.0''',
      ),
    );

    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^2.0.0', 'bar': '^2.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^2.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).validate();
  });
  test('`upgrade --major-versions foo` upgrades foo in all workspace',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.5.0');
    server.serve('foo', '2.0.0');
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.0.0', 'bar': '1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '1.5.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('+ foo 1.5.0'),
    );
    await pubUpgrade(
      args: ['--major-versions', 'foo'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
Changed 1 constraint in pubspec.yaml:
  foo: ^1.0.0 -> ^2.0.0

Changed 1 constraint in a${s}pubspec.yaml:
  foo: 1.5.0 -> ^2.0.0''',
      ),
    );
    // Second run should mention "any pubspec.yaml".
    await pubUpgrade(
      args: ['--major-versions', 'foo'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
No changes to any pubspec.yaml!''',
      ),
    );
    await pubUpgrade(
      args: ['--major-versions', 'foo', '--dry-run'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
No changes would be made to any pubspec.yaml!''',
      ),
    );

    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^2.0.0', 'bar': '1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^2.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).validate();
  });

  test('`upgrade --tighten` updates all workspace', () async {
    final server = await servePackages();
    server.serve('foo', '1.5.0');
    server.serve('bar', '1.5.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.0.0', 'bar': '^1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a', 'b'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^1.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
      dir('b', [
        libPubspec(
          'b',
          '1.0.0',
          deps: {'bar': '^1.5.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('+ foo 1.5.0'),
    );
    await pubUpgrade(
      args: ['--tighten'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
Changed 2 constraints in pubspec.yaml:
  foo: ^1.0.0 -> ^1.5.0
  bar: ^1.0.0 -> ^1.5.0

Changed 1 constraint in a${s}pubspec.yaml:
  foo: ^1.0.0 -> ^1.5.0''',
      ),
    );

    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.5.0', 'bar': '^1.5.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a', 'b'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^1.5.0'},
          resolutionWorkspace: true,
        ),
      ]),
      dir('b', [
        libPubspec(
          'b',
          '1.0.0',
          deps: {'bar': '^1.5.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).validate();
  });

  test('`upgrade --major-versions --tighten` updates all workspace', () async {
    final server = await servePackages();
    server.serve('foo', '1.5.0');
    server.serve('bar', '1.5.0');
    server.serve('foo', '2.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '^1.0.0', 'bar': '^1.0.0'},
        sdk: '^3.5.0',
        extras: {
          'workspace': ['a', 'b'],
        },
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          deps: {'foo': '^1.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
      dir('b', [
        libPubspec(
          'b',
          '1.0.0',
          deps: {'bar': '^1.0.0'},
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('+ foo 1.5.0'),
    );
    await pubUpgrade(
      args: ['--tighten', '--major-versions'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains(
        '''
Changed 2 constraints in pubspec.yaml:
  foo: ^1.0.0 -> ^2.0.0
  bar: ^1.0.0 -> ^1.5.0

Changed 1 constraint in a${s}pubspec.yaml:
  foo: ^1.0.0 -> ^2.0.0

Changed 1 constraint in b${s}pubspec.yaml:
  bar: ^1.0.0 -> ^1.5.0''',
      ),
    );
  });

  // TODO(https://github.com/dart-lang/pub/issues/4227): we want to enable this at some point.
  test('No suggestions for workspaces', () async {
    final server = await servePackages();
    server.serve('dev_dep', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {
          'a': '2.0.0',
        }, // Would provoke a suggestion to update the constraint.
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec(
            'a',
            '1.0.0',
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error:
          'Because myapp depends on both a 2.0.0 and a, version solving failed.',
    );
  });

  test('Reports error if two members of workspace has same name', () async {
    final server = await servePackages();
    server.serve('dev_dep', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['a', 'b'],
        },
        sdk: '^3.5.0',
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          resolutionWorkspace: true,
        ),
      ]),
      dir('b', [
        libPubspec(
          'a', // Has same name as sibling.
          '1.0.0',
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: '''
Workspace members must have unique names.
`a${s}pubspec.yaml` and `b${s}pubspec.yaml` are both called "a".''',
    );
  });

  test('Reports error if two members of workspace override the same package',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': 'any'},
        extras: {
          'dependency_overrides': {
            'foo': {'path': '../foo'},
          },
          'workspace': ['a'],
        },
        sdk: '^3.5.0',
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          resolutionWorkspace: true,
        ),
        pubspecOverrides({
          'dependency_overrides': {'foo': '2.0.0'},
        }),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: '''
The package `foo` is overridden in both:
package `myapp` at `.` and 'a' at `.${s}a`.

Consider removing one of the overrides.''',
    );
  });

  test('overrides are applied', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await dir('foo', [libPubspec('foo', '1.0.1')]).create();
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        deps: {'foo': '1.0.0'},
        extras: {
          'workspace': ['a'],
        },
        sdk: '^3.5.0',
      ),
      dir('a', [
        libPubspec(
          'a',
          '1.0.0',
          extras: {
            'dependency_overrides': {
              'foo': {'path': '../../foo'},
            },
          },
          resolutionWorkspace: true,
        ),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('! foo 1.0.1 from path ..${s}foo (overridden)'),
    );
  });

  test('Can publish from workspace', () async {
    final server = await servePackages();
    await credentialsFile(server, 'access-token').create();
    server.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'},
        }),
      );
    });
    await dir('workspace', [
      libPubspec(
        'workspace',
        '1.2.3',
        extras: {
          'workspace': [appPath],
        },
        sdk: '^3.5.0',
      ),
      validPackage(
        pubspecExtras: {
          'environment': {'sdk': '^3.5.0'},
          'resolution': 'workspace',
        },
      ),
    ]).create();

    await runPub(
      args: ['publish', '--to-archive=archive.tar.gz'],
      workingDirectory: p.join(sandbox, 'workspace', appPath),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('''
├── CHANGELOG.md (<1 KB)
├── LICENSE (<1 KB)
├── README.md (<1 KB)
├── lib
│   └── test_pkg.dart (<1 KB)
└── pubspec.yaml (<1 KB)
'''),
    );

    final pub = await startPublish(
      server,
      workingDirectory: p.join(sandbox, 'workspace', appPath),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );

    await confirmPublish(pub);
    handleUploadForm(server);
    handleUpload(server);
    await pub.shouldExit(SUCCESS);
  });

  test(
      'published packages with `resolution: workspace` and `workspace` sections can be consumed out of context.',
      () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '^3.5.0'},
        'resolution': 'workspace',
        'workspace': ['example'],
      },
      contents: [
        dir('bin', [file('foo.dart', 'main() => print("FOO");')]),
      ],
    );
    await appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
    await runPub(
      args: ['run', 'foo'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      output: contains('FOO'),
    );
  });

  test('Cannot override workspace packages', () async {
    await servePackages();
    await dir(appPath, [
      libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
          'dependency_overrides': {
            'a': {'path': 'pkgs/a'},
          },
        },
        sdk: '^3.5.0',
      ),
      dir('pkgs', [
        dir('a', [
          libPubspec('a', '1.1.1', resolutionWorkspace: true),
        ]),
      ]),
    ]).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: allOf(
        contains('Cannot override workspace packages'),
        contains(
          'Package `a` at `.${s}pkgs/a` is overridden in `pubspec.yaml`.',
        ),
      ),
    );
  });
}

final s = p.separator;
