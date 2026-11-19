// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  setUp(() async {
    await servePackages()
      ..serve(
        'normal',
        '1.2.3',
        deps: {'transitive': 'any', 'circular_a': 'any'},
      )
      ..serve('transitive', '1.2.3', deps: {'shared': 'any'})
      ..serve('shared', '1.2.3', deps: {'other': 'any'})
      ..serve('dev_only', '1.2.3')
      ..serve('unittest', '1.2.3', deps: {'shared': 'any', 'dev_only': 'any'})
      ..serve('other', '1.0.0', deps: {'myapp': 'any'})
      ..serve('overridden', '1.0.0')
      ..serve('overridden', '2.0.0')
      ..serve('override_only', '1.2.3')
      ..serve('circular_a', '1.2.3', deps: {'circular_b': 'any'})
      ..serve('circular_b', '1.2.3', deps: {'circular_a': 'any'});

    await d.dir('from_path', [
      d.libDir('from_path'),
      d.libPubspec('from_path', '1.2.3'),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'normal': 'any',
          'overridden': '1.0.0',
          'from_path': {'path': '../from_path'},
        },
        'dev_dependencies': {'unittest': 'any'},
        'dependency_overrides': {'overridden': '2.0.0', 'override_only': 'any'},
      }),
    ]).create();
  });

  group('lists all dependencies', () {
    test('in compact form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '-s', 'compact'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0

          dependencies:
          - from_path 1.2.3
          - normal 1.2.3 [transitive circular_a]
          - overridden 2.0.0

          dev dependencies:
          - unittest 1.2.3 [shared dev_only]

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3 [circular_b]
          - circular_b 1.2.3 [circular_a]
          - dev_only 1.2.3
          - other 1.0.0 [myapp]
          - shared 1.2.3 [other]
          - transitive 1.2.3 [shared]
          ''',
      );
    });

    test('in list form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '--style', 'list'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0

          dependencies:
          - normal 1.2.3
            - transitive any
            - circular_a any
          - overridden 2.0.0
          - from_path 1.2.3

          dev dependencies:
          - unittest 1.2.3
            - shared any
            - dev_only any

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3
            - circular_b any
          - circular_b 1.2.3
            - circular_a any
          - dev_only 1.2.3
          - other 1.0.0
            - myapp any
          - shared 1.2.3
            - other any
          - transitive 1.2.3
            - shared any
          ''',
      );
    });

    test('in tree form', () async {
      await pubGet();
      await runPub(
        args: ['deps'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0
          ├── from_path 1.2.3
          ├── normal 1.2.3
          │   ├── circular_a 1.2.3
          │   │   └── circular_b 1.2.3
          │   │       └── circular_a...
          │   └── transitive 1.2.3
          │       └── shared...
          ├── overridden 2.0.0
          ├── override_only 1.2.3
          └── unittest 1.2.3
              ├── dev_only 1.2.3
              └── shared 1.2.3
                  └── other 1.0.0
                      └── myapp...
          ''',
      );
    });
    test('in json form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '--json'],
        output: '''
{
  "root": "myapp",
  "packages": [
    {
      "name": "myapp",
      "version": "0.0.0",
      "kind": "root",
      "source": "root",
      "dependencies": [
        "normal",
        "overridden",
        "from_path",
        "unittest",
        "override_only"
      ],
      "directDependencies": [
        "normal",
        "overridden",
        "from_path"
      ],
      "devDependencies": [
        "unittest"
      ],
      "dependencyConstraints": {
        "normal": "any",
        "overridden": "2.0.0",
        "from_path": "any",
        "unittest": "any",
        "override_only": "any"
      }
    },
    {
      "name": "override_only",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [],
      "directDependencies": [],
      "dependencyConstraints": {}
    },
    {
      "name": "unittest",
      "version": "1.2.3",
      "kind": "dev",
      "source": "hosted",
      "dependencies": [
        "shared",
        "dev_only"
      ],
      "directDependencies": [
        "shared",
        "dev_only"
      ],
      "dependencyConstraints": {
        "shared": "any",
        "dev_only": "any"
      }
    },
    {
      "name": "dev_only",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [],
      "directDependencies": [],
      "dependencyConstraints": {}
    },
    {
      "name": "shared",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [
        "other"
      ],
      "directDependencies": [
        "other"
      ],
      "dependencyConstraints": {
        "other": "any"
      }
    },
    {
      "name": "other",
      "version": "1.0.0",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [
        "myapp"
      ],
      "directDependencies": [
        "myapp"
      ],
      "dependencyConstraints": {
        "myapp": "any"
      }
    },
    {
      "name": "from_path",
      "version": "1.2.3",
      "kind": "direct",
      "source": "path",
      "dependencies": [],
      "directDependencies": [],
      "dependencyConstraints": {}
    },
    {
      "name": "overridden",
      "version": "2.0.0",
      "kind": "direct",
      "source": "hosted",
      "dependencies": [],
      "directDependencies": [],
      "dependencyConstraints": {}
    },
    {
      "name": "normal",
      "version": "1.2.3",
      "kind": "direct",
      "source": "hosted",
      "dependencies": [
        "transitive",
        "circular_a"
      ],
      "directDependencies": [
        "transitive",
        "circular_a"
      ],
      "dependencyConstraints": {
        "transitive": "any",
        "circular_a": "any"
      }
    },
    {
      "name": "circular_a",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [
        "circular_b"
      ],
      "directDependencies": [
        "circular_b"
      ],
      "dependencyConstraints": {
        "circular_b": "any"
      }
    },
    {
      "name": "circular_b",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [
        "circular_a"
      ],
      "directDependencies": [
        "circular_a"
      ],
      "dependencyConstraints": {
        "circular_a": "any"
      }
    },
    {
      "name": "transitive",
      "version": "1.2.3",
      "kind": "transitive",
      "source": "hosted",
      "dependencies": [
        "shared"
      ],
      "directDependencies": [
        "shared"
      ],
      "dependencyConstraints": {
        "shared": "any"
      }
    }
  ],
  "sdks": [
    {
      "name": "Dart",
      "version": "3.1.2+3"
    }
  ],
  "executables": []
}''',
      );
    });

    test('with the Flutter SDK, if applicable', () async {
      await pubGet();

      await d.dir('flutter', [d.flutterVersion('4.3.2+1')]).create();
      await runPub(
        args: ['deps'],
        output: contains('Flutter SDK 4.3.2+1'),
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
      );
    });

    test('with the Fuchsia SDK, if applicable', () async {
      await pubGet();

      await d.dir('fuchsia', [d.file('version', '4.3.2+1')]).create();
      await runPub(
        args: ['deps'],
        output: contains('Fuchsia SDK 4.3.2+1'),
        environment: {'FUCHSIA_DART_SDK_ROOT': p.join(d.sandbox, 'fuchsia')},
      );
    });
  });

  group('lists non-dev dependencies', () {
    test('in compact form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '-s', 'compact', '--no-dev'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0

          dependencies:
          - from_path 1.2.3
          - normal 1.2.3 [transitive circular_a]
          - overridden 2.0.0

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3 [circular_b]
          - circular_b 1.2.3 [circular_a]
          - other 1.0.0 [myapp]
          - shared 1.2.3 [other]
          - transitive 1.2.3 [shared]
          ''',
      );
    });

    test('in list form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '--style', 'list', '--no-dev'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0

          dependencies:
          - normal 1.2.3
            - transitive any
            - circular_a any
          - overridden 2.0.0
          - from_path 1.2.3

          dependency overrides:
          - overridden 2.0.0
          - override_only 1.2.3

          transitive dependencies:
          - circular_a 1.2.3
            - circular_b any
          - circular_b 1.2.3
            - circular_a any
          - other 1.0.0
            - myapp any
          - shared 1.2.3
            - other any
          - transitive 1.2.3
            - shared any
          ''',
      );
    });

    test('in tree form', () async {
      await pubGet();
      await runPub(
        args: ['deps', '--no-dev'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0
          ├── from_path 1.2.3
          ├── normal 1.2.3
          │   ├── circular_a 1.2.3
          │   │   └── circular_b 1.2.3
          │   │       └── circular_a...
          │   └── transitive 1.2.3
          │       └── shared 1.2.3
          │           └── other 1.0.0
          │               └── myapp...
          ├── overridden 2.0.0
          └── override_only 1.2.3
          ''',
      );
    });
  });

  group('explains why specific packages are included', () {
    test('in inverted tree form by default', () async {
      await pubGet();
      await runPub(
        args: ['deps', 'shared'],
        output: '''
          Dart SDK 3.1.2+3
          shared 1.2.3
          ├── transitive 1.2.3 (any)
          │   └── normal 1.2.3 (any)
          │       └── myapp 0.0.0 (any)
          └── unittest 1.2.3 (any)
              └── myapp 0.0.0 (any, dev)
          ''',
      );
    });

    test('in inverted tree form with --no-dev', () async {
      await pubGet();
      await runPub(
        args: ['deps', 'shared', '--no-dev'],
        output: '''
          Dart SDK 3.1.2+3
          shared 1.2.3
          └── transitive 1.2.3 (any)
              └── normal 1.2.3 (any)
                  └── myapp 0.0.0 (any)
          ''',
      );
    });

    test(
      'in inverted tree form for overridden and circular packages',
      () async {
        await pubGet();
        await runPub(
          args: ['deps', 'overridden', 'override_only', 'circular_a'],
          output: '''
          Dart SDK 3.1.2+3
          circular_a 1.2.3
          ├── circular_b 1.2.3 (any)
          │   └── circular_a... (any)
          └── normal 1.2.3 (any)
              └── myapp 0.0.0 (any)
          overridden 2.0.0
          └── myapp 0.0.0 (1.0.0, override: 2.0.0)
          override_only 1.2.3
          └── myapp 0.0.0 (override: any)
          ''',
        );
      },
    );

    test('in top-down tree form with --from-root', () async {
      await pubGet();
      await runPub(
        args: ['deps', 'shared', '--from-root'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0
          ├── normal 1.2.3 (any)
          │   └── transitive 1.2.3 (any)
          │       └── shared 1.2.3 (any)
          └── unittest 1.2.3 (any, dev)
              └── shared 1.2.3 (any)
          ''',
      );
    });

    test('in top-down tree form with --from-root and --no-dev', () async {
      await pubGet();
      await runPub(
        args: ['deps', 'shared', '--from-root', '--no-dev'],
        output: '''
          Dart SDK 3.1.2+3
          myapp 0.0.0
          └── normal 1.2.3 (any)
              └── transitive 1.2.3 (any)
                  └── shared 1.2.3 (any)
          ''',
      );
    });

    test('errors when package is not a dependency', () async {
      await pubGet();
      await runPub(
        args: ['deps', 'nonexistent'],
        error: 'Package "nonexistent" is not a dependency.',
        exitCode: 65,
      );
    });

    test(
      'errors when package is only a dev dependency with --no-dev',
      () async {
        await pubGet();
        await runPub(
          args: ['deps', 'dev_only', '--no-dev'],
          error:
              'Package "dev_only" is only included via dev_dependencies. '
              'Run without --no-dev to see paths.',
          exitCode: 65,
        );
      },
    );

    test('rejects incompatible flags', () async {
      await pubGet();
      await runPub(
        args: ['deps', '--from-root'],
        error: contains('Cannot specify --from-root without target packages.'),
        exitCode: 64,
      );
      await runPub(
        args: ['deps', 'shared', '--json'],
        error: contains('Cannot combine --json and package arguments.'),
        exitCode: 64,
      );
      await runPub(
        args: ['deps', 'shared', '--executables'],
        error: contains('Cannot combine --executables and package arguments.'),
        exitCode: 64,
      );
      await runPub(
        args: ['deps', 'shared', '--style=compact'],
        error: contains(
          'Cannot combine --style=compact and package arguments.',
        ),
        exitCode: 64,
      );
    });

    test('works across workspace packages', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'myapp',
          '0.0.0',
          deps: {'normal': '^1.0.0'},
          extras: {
            'workspace': ['pkgs/sub_a'],
          },
          sdk: '^3.5.0',
        ),
        d.dir('pkgs', [
          d.dir('sub_a', [
            d.libPubspec(
              'sub_a',
              '1.0.0',
              deps: {'shared': '^1.0.0'},
              resolutionWorkspace: true,
            ),
          ]),
        ]),
      ]).create();

      await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
      await runPub(
        args: ['deps', 'shared'],
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        output: '''
          Dart SDK 3.5.0
          shared 1.2.3
          ├── sub_a 1.0.0 (^1.0.0)
          └── transitive 1.2.3 (any)
              └── normal 1.2.3 (any)
                  └── myapp 0.0.0 (^1.0.0)
          ''',
      );
      await runPub(
        args: ['deps', 'shared', '--from-root'],
        environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
        output: '''
          Dart SDK 3.5.0
          myapp 0.0.0
          └── normal 1.2.3 (^1.0.0)
              └── transitive 1.2.3 (any)
                  └── shared 1.2.3 (any)
          sub_a 1.0.0
          └── shared 1.2.3 (^1.0.0)
          ''',
      );
    });
  });
}
