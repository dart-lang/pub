// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  group('pub upgrade --null-safety', () {
    setUp(() async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.10.0<3.0.0'},
        });
        builder.serve('foo', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.12.0<3.0.0'},
        });
        builder.serve('bar', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        });
        builder.serve('bar', '2.0.0-nullsafety.0', pubspec: {
          'environment': {'sdk': '>=2.12.0<3.0.0'},
        });
        builder.serve('baz', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        });
        builder.serve('has_conflict', '1.0.0', pubspec: {
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        });
        builder.serve('has_conflict', '2.0.0', pubspec: {
          'environment': {'sdk': '>=2.13.0<3.0.0'},
        });
      });
    });

    test('upgrades to null-safety versions', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });
      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.0.0',
            languageVersion: '2.10',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.10.0'),
      ]).validate();

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
        ),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^2.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '2.0.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.12.0'),
      ]).validate();
    });

    test('upgrades to prereleases when required', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'bar': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });
      await d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'bar',
            version: '1.0.0',
            languageVersion: '2.9',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.10.0'),
      ]).validate();

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
        ),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'bar': '^2.0.0-nullsafety.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'bar',
            version: '2.0.0-nullsafety.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.12.0'),
      ]).validate();
    });

    test('upgrades multiple dependencies', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
        ),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^2.0.0',
            'bar': '^2.0.0-nullsafety.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '2.0.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '2.0.0-nullsafety.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.12.0'),
      ]).validate();
    });

    test('--dry-run does not mutate pubspec.yaml', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });

      final stateBeforeUpgrade = d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '1.0.0',
            languageVersion: '2.10',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '1.0.0',
            languageVersion: '2.9',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.10.0'),
      ]);
      await stateBeforeUpgrade.validate();

      await pubUpgrade(
        args: ['--null-safety', '--dry-run'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Would change 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
        ),
      );

      await stateBeforeUpgrade.validate();
    });

    test('ignores path dependencies', () async {
      await d.dir('baz', [
        d.pubspec({
          'name': 'baz',
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
            'baz': {
              'path': d.path('baz'),
            },
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
        ),
        warning: allOf(
          contains('Following direct \'dependencies\' and'),
          contains('\'dev_dependencies\' are not migrated to'),
          contains('null-safety yet:'),
          contains(' - baz'),
        ),
      );
    });

    test('cannot upgrade without null-safety versions', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
            'baz': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        error: allOf(
          contains('null-safety compatible versions do not exist for:'),
          contains(' - baz'),
          contains('You can choose to upgrade only some dependencies'),
          contains('dart pub upgrade --nullsafety'),
          contains('https://dart.dev/null-safety/migration-guide'),
        ),
      );
    });

    test('can upgrade partially', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
            'baz': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubUpgrade(
        args: ['--null-safety', 'bar', 'foo'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        output: allOf(
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
        ),
        warning: allOf(
          contains('Following direct \'dependencies\' and'),
          contains('\'dev_dependencies\' are not migrated to'),
          contains('null-safety yet:'),
          contains(' - baz'),
        ),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^2.0.0',
            'bar': '^2.0.0-nullsafety.0',
            'baz': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'foo',
            version: '2.0.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'bar',
            version: '2.0.0-nullsafety.0',
            languageVersion: '2.12',
          ),
          d.packageConfigEntry(
            name: 'baz',
            version: '1.0.0',
            languageVersion: '2.9',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            languageVersion: '2.9',
            path: '.',
          ),
        ], generatorVersion: '2.12.0'),
      ]).validate();
    });

    test('can fail to solve', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
            // This causes a SDK constraint conflict when migrating to
            // null-safety
            'has_conflict': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.12.0',
        },
        error: allOf(
          contains('Because myapp depends on has_conflict >=2.0.0 which'),
          contains('requires SDK version >=2.13.0 <3.0.0,'),
          contains('version solving failed.'),
        ),
      );
    });

    test('works in 2.14.0', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': '^1.0.0',
            'bar': '^1.0.0',
            // This requires SDK >= 2.13.0
            'has_conflict': '^1.0.0',
          },
          'environment': {'sdk': '>=2.9.0<3.0.0'},
        }),
      ]).create();

      await pubGet(environment: {
        '_PUB_TEST_SDK_VERSION': '2.10.0',
      });

      await pubUpgrade(
        args: ['--null-safety'],
        environment: {
          '_PUB_TEST_SDK_VERSION': '2.14.0',
        },
        output: allOf(
          contains('Changed 3 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^2.0.0-nullsafety.0'),
          contains('has_conflict: ^1.0.0 -> ^2.0.0'),
        ),
      );
    });
  });
}
