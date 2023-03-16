// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show File;

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('URL encodes the package name', () async {
    await servePackages();

    await d.appDir(dependencies: {}).create();

    await pubAdd(
      args: ['bad name!:1.2.3'],
      error: contains('Not a valid package name: "bad name!"'),
      exitCode: exit_codes.USAGE,
    );

    await d.appDir(dependencies: {}).validate();

    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('adds a package with a multi-component name from path', () async {
    await d.dir('foo', [d.libPubspec('fo_o1.a', '1.0.0')]).create();

    await d.appDir(dependencies: {}).create();

    await pubAdd(args: ['fo_o1.a:{"path":"../foo"}']);

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'fo_o1.a', path: '../foo'),
    ]).validate();
    await d.appDir(
      dependencies: {
        'fo_o1.a': {'path': '../foo'}
      },
    ).validate();
  });

  group('normally', () {
    test('adds a package from a pub server', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.appDir(dependencies: {}).create();

      await pubAdd(args: ['foo:1.2.3']);

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();
      await d.appDir(dependencies: {'foo': '1.2.3'}).validate();
    });

    test('adds multiple package from a pub server', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      server.serve('bar', '1.1.0');
      server.serve('baz', '2.5.3');

      await d.appDir(dependencies: {}).create();

      await pubAdd(args: ['foo:1.2.3', 'bar:1.1.0', 'baz:2.5.3']);

      await d.cacheDir(
        {'foo': '1.2.3', 'bar': '1.1.0', 'baz': '2.5.3'},
      ).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
        d.packageConfigEntry(name: 'bar', version: '1.1.0'),
        d.packageConfigEntry(name: 'baz', version: '2.5.3'),
      ]).validate();
      await d.appDir(
        dependencies: {'foo': '1.2.3', 'bar': '1.1.0', 'baz': '2.5.3'},
      ).validate();
    });

    test(
        'does not remove empty dev_dependencies while adding to normal dependencies',
        () async {
      await servePackages()
        ..serve('foo', '1.2.3')
        ..serve('foo', '1.2.2');

      await d.dir(appPath, [
        d.file('pubspec.yaml', '''
          name: myapp
          dependencies:

          dev_dependencies:

          environment:
            sdk: $defaultSdkConstraint
        ''')
      ]).create();

      await pubAdd(args: ['foo:1.2.3']);

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.3'},
          'dev_dependencies': null
        })
      ]).validate();
    });

    test('dry run does not actually add the package or modify the pubspec',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.appDir(dependencies: {}).create();

      await pubAdd(
        args: ['foo:1.2.3', '--dry-run'],
        output: allOf(
          [contains('Would change 1 dependency'), contains('+ foo 1.2.3')],
        ),
      );

      await d.appDir(dependencies: {}).validate();
      await d.dir(appPath, [
        d.nothing('.dart_tool/package_config.json'),
        d.nothing('pubspec.lock'),
        d.nothing('.packages'),
      ]).validate();
    });

    test(
        'adds a package from a pub server even when dependencies key does not exist',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.dir(appPath, [
        d.file('pubspec.yaml', '''
name: myapp
environment:
  "sdk": "$defaultSdkConstraint"
''')
      ]).create();

      await pubAdd(args: ['foo:1.2.3']);
      final yaml = loadYaml(
        File(p.join(d.sandbox, appPath, 'pubspec.yaml')).readAsStringSync(),
      );

      expect(
        ((yaml as YamlMap).nodes['dependencies'] as YamlMap).style,
        CollectionStyle.BLOCK,
        reason: 'Should create the mapping with block-style by default',
      );
      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();
      await d.appDir(dependencies: {'foo': '1.2.3'}).validate();
    });

    test('Inserts correctly when the pubspec is flow-style at top-level',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.dir(appPath, [
        d.file(
          'pubspec.yaml',
          '{"name":"myapp", "environment": {"sdk": "$defaultSdkConstraint"}}',
        )
      ]).create();

      await pubAdd(args: ['foo:1.2.3']);

      final yaml = loadYaml(
        File(p.join(d.sandbox, appPath, 'pubspec.yaml')).readAsStringSync(),
      );

      expect(
        ((yaml as YamlMap).nodes['dependencies'] as YamlMap).style,
        CollectionStyle.FLOW,
        reason: 'Should not break a pubspec in flow-style',
      );

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();
      await d.appDir(dependencies: {'foo': '1.2.3'}).validate();
    });

    group('notifies user about existing constraint', () {
      test('if package is added without a version constraint', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.appDir(dependencies: {'foo': '1.2.2'}).create();

        await pubAdd(
          args: ['foo'],
          output: contains(
            '"foo" is already in "dependencies". Will try to update the constraint.',
          ),
        );

        await d.appDir(dependencies: {'foo': '^1.2.3'}).validate();
      });

      test('if package is added with a specific version constraint', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.appDir(dependencies: {'foo': '1.2.2'}).create();

        await pubAdd(
          args: ['foo:1.2.3'],
          output: contains(
            '"foo" is already in "dependencies". Will try to update the constraint.',
          ),
        );

        await d.appDir(dependencies: {'foo': '1.2.3'}).validate();
      });

      test('if package is added with a version constraint range', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.appDir(dependencies: {'foo': '1.2.2'}).create();

        await pubAdd(
          args: ['foo:>=1.2.2'],
          output: contains(
            '"foo" is already in "dependencies". Will try to update the constraint.',
          ),
        );

        await d.appDir(dependencies: {'foo': '>=1.2.2'}).validate();
      });
    });

    test('removes dev_dependency and add to normal dependency', () async {
      await servePackages()
        ..serve('foo', '1.2.3')
        ..serve('foo', '1.2.2');

      await d.dir(appPath, [
        d.file('pubspec.yaml', '''
name: myapp
dependencies: 

dev_dependencies:
  foo: 1.2.2
environment:
  sdk: '$defaultSdkConstraint'
''')
      ]).create();

      await pubAdd(
        args: ['foo:1.2.3'],
        output:
            contains('"foo" was found in dev_dependencies. Removing "foo" and '
                'adding it to dependencies instead.'),
      );

      await d.cacheDir({'foo': '1.2.3'}).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.3'}
        })
      ]).validate();
    });

    group('dependency override', () {
      test('passes if package does not specify a range', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo']);

        await d.cacheDir({'foo': '1.2.2'}).validate();
        await d.appPackageConfigFile([
          d.packageConfigEntry(name: 'foo', version: '1.2.2'),
        ]).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '^1.2.2'},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).validate();
      });

      test('passes if constraint matches git dependency override', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');

        await d.git(
          'foo.git',
          [d.libDir('foo'), d.libPubspec('foo', '1.2.3')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.3']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '1.2.3'},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).validate();
      });

      test('passes if constraint matches path dependency override', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.2');
        await d.dir(
          'foo',
          [d.libDir('foo'), d.libPubspec('foo', '1.2.2')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.2']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {'foo': '1.2.2'},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).validate();
      });

      test('fails with bad version constraint', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');

        await d.dir(appPath, [
          d.pubspec({'name': 'myapp', 'dependencies': {}})
        ]).create();

        await pubAdd(
          args: ['foo:one-two-three'],
          exitCode: exit_codes.DATA,
          error: contains('Invalid version constraint: Could '
              'not parse version "one-two-three".'),
        );

        await d.dir(appPath, [
          d.pubspec({'name': 'myapp', 'dependencies': {}}),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match override', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.3'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.2.2" which does not satisfy constraint '
              '"1.2.3". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint matches git dependency override', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');

        await d.git(
          'foo.git',
          [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.3'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.0.0" which does not satisfy constraint '
              '"1.2.3". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match path dependency override',
          () async {
        final server = await servePackages();
        server.serve('foo', '1.2.2');
        await d.dir(
          'foo',
          [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.2'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.0.0" which does not satisfy constraint '
              '"1.2.2". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });
    });
  });

  test('Cannot combine descriptor with old-style args', () async {
    await d.appDir().create();

    await pubAdd(
      args: ['foo:{"path":"../foo"}', '--path=../foo'],
      error: contains(
        '--dev, --path, --sdk, --git-url, --git-path and --git-ref cannot be combined',
      ),
      exitCode: exit_codes.USAGE,
    );
  });

  group('--dev', () {
    test('--dev adds packages to dev_dependencies instead', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(args: ['--dev', 'foo:1.2.3']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {'foo': '1.2.3'}
        })
      ]).validate();
    });

    test('--dev cannot be used with a descriptor', () async {
      await d.dir('foo', [d.libPubspec('foo', '1.2.3')]).create();

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(
        args: ['--dev', 'foo:{"path":../foo}'],
        error: contains(
          '--dev, --path, --sdk, --git-url, --git-path and --git-ref cannot be combined',
        ),
        exitCode: exit_codes.USAGE,
      );
    });

    test('dev: adds packages to dev_dependencies instead without a descriptor',
        () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(args: ['dev:foo:1.2.3']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      ]).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {'foo': '1.2.3'}
        })
      ]).validate();
    });

    test('Cannot combine --dev with :dev', () async {
      await d.dir('foo', [d.libPubspec('foo', '1.2.3')]).create();

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(
        args: ['--dev', 'dev:foo:1.2.3'],
        error: contains("Cannot combine 'dev:' with --dev"),
        exitCode: exit_codes.USAGE,
      );
    });

    test('Can add both dev and regular dependencies', () async {
      final server = await servePackages();
      server.serve('foo', '1.2.3');
      server.serve('bar', '1.2.3');

      await d.dir(appPath, [
        d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
      ]).create();

      await pubAdd(args: ['dev:foo:1.2.3', 'bar:1.2.3']);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.2.3'),
        d.packageConfigEntry(name: 'bar', version: '1.2.3'),
      ]).validate();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'bar': '1.2.3'},
          'dev_dependencies': {'foo': '1.2.3'},
        })
      ]).validate();
    });

    group('notifies user if package exists', () {
      test('if package is added without a version constraint', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
          args: ['foo', '--dev'],
          output: contains(
            '"foo" is already in "dev_dependencies". Will try to update the constraint.',
          ),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '^1.2.3'}
          })
        ]).validate();
      });

      test('if package is added with a specific version constraint', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.3', '--dev'],
          output: contains(
            '"foo" is already in "dev_dependencies". Will try to update the constraint.',
          ),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.3'}
          })
        ]).validate();
      });

      test('if package is added with a version constraint range', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
          args: ['foo:>=1.2.2', '--dev'],
          output: contains(
            '"foo" is already in "dev_dependencies". Will try to update the constraint.',
          ),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '>=1.2.2'}
          })
        ]).validate();
      });
    });

    group('dependency override', () {
      test('passes if package does not specify a range', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(args: ['foo', '--dev']);

        await d.cacheDir({'foo': '1.2.2'}).validate();
        await d.appPackageConfigFile([
          d.packageConfigEntry(name: 'foo', version: '1.2.2'),
        ]).validate();
        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '^1.2.2'},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).validate();
      });

      test('passes if constraint is git dependency', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');
        await d.git(
          'foo.git',
          [d.libDir('foo'), d.libPubspec('foo', '1.2.3')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.3', '--dev']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.3'},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).validate();
      });

      test('passes if constraint matches path dependency override', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.2');
        await d.dir(
          'foo',
          [d.libDir('foo'), d.libPubspec('foo', '1.2.2')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(args: ['foo:1.2.2', '--dev']);

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {'foo': '1.2.2'},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).validate();
      });

      test('fails if constraint does not match override', () async {
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.2');

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.3', '--dev'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.2.2" which does not satisfy constraint '
              '"1.2.3". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {'foo': '1.2.2'}
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint matches git dependency override', () async {
        final server = await servePackages();
        server.serve('foo', '1.2.3');

        await d.git(
          'foo.git',
          [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.3'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.0.0" which does not satisfy constraint '
              '"1.2.3". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'git': '../foo.git'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });

      test('fails if constraint does not match path dependency override',
          () async {
        final server = await servePackages();
        server.serve('foo', '1.2.2');

        await d.dir(
          'foo',
          [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
        ).create();

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          })
        ]).create();

        await pubAdd(
          args: ['foo:1.2.2', '--dev'],
          exitCode: exit_codes.DATA,
          error: contains(
              '"foo" resolved to "1.0.0" which does not satisfy constraint '
              '"1.2.2". This could be caused by "dependency_overrides".'),
        );

        await d.dir(appPath, [
          d.pubspec({
            'name': 'myapp',
            'dev_dependencies': {},
            'dependency_overrides': {
              'foo': {'path': '../foo'}
            }
          }),
          d.nothing('.dart_tool/package_config.json'),
          d.nothing('pubspec.lock'),
          d.nothing('.packages'),
        ]).validate();
      });
    });

    test(
        'prints information saying that package is already a dependency if it '
        'already exists and exits with a usage exception', () async {
      await servePackages()
        ..serve('foo', '1.2.3')
        ..serve('foo', '1.2.2');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.2'},
          'dev_dependencies': {}
        })
      ]).create();

      await pubAdd(
        args: ['foo:1.2.3', '--dev'],
        error: contains('"foo" is already in "dependencies". Use '
            '"pub remove foo" to remove it before adding it to '
            '"dev_dependencies"'),
        exitCode: exit_codes.DATA,
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '1.2.2'},
          'dev_dependencies': {}
        }),
        d.nothing('.dart_tool/package_config.json'),
        d.nothing('pubspec.lock'),
        d.nothing('.packages'),
      ]).validate();
    });
  });

  /// Differs from the previous test because this tests YAML in flow format.
  test('adds to empty ', () async {
    final server = await servePackages();
    server.serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
        name: myapp
        dependencies:
        environment:
          sdk: '$defaultSdkConstraint'
'''),
    ]).create();

    await pubGet();

    await pubAdd(args: ['bar']);
    await d.appDir(dependencies: {'bar': '^1.0.0'}).validate();
  });

  test('preserves comments', () async {
    await servePackages()
      ..serve('bar', '1.0.0')
      ..serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
        name: myapp
        dependencies: # comment A
            # comment B
            foo: 1.0.0 # comment C
          # comment D
        environment:
          sdk: '$defaultSdkConstraint'
    '''),
    ]).create();

    await pubGet();

    await pubAdd(args: ['bar']);

    await d.appDir(dependencies: {'bar': '^1.0.0', 'foo': '1.0.0'}).validate();
    final fullPath = p.join(d.sandbox, appPath, 'pubspec.yaml');

    expect(File(fullPath).existsSync(), true);

    final contents = File(fullPath).readAsStringSync();
    expect(
      contents,
      allOf([
        contains('# comment A'),
        contains('# comment B'),
        contains('# comment C'),
        contains('# comment D')
      ]),
    );
  });

  test('adds to overrides', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');

    await d.dir('local_foo', [d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
dependencies:
  foo: ^1.0.0
environment:
  sdk: '$defaultSdkConstraint'
'''),
    ]).create();

    await pubGet();

    await pubAdd(
      args: ['override:bar'],
      exitCode: exit_codes.USAGE,
      error: contains('A dependency override needs an explicit descriptor.'),
    );

    // Can override a transitive dependency.
    await pubAdd(args: ['override:bar:2.0.0']);
    await d.dir(appPath, [
      d.file(
        'pubspec.yaml',
        contains('''
dependency_overrides:
  bar: 2.0.0
'''),
      )
    ]).validate();

    // Can override with a descriptor:
    await pubAdd(args: ['override:foo:{"path": "../local_foo"}']);

    await d.dir(appPath, [
      d.file(
        'pubspec.yaml',
        contains('''
dependency_overrides:
  bar: 2.0.0
  foo:
    path: ../local_foo
'''),
      )
    ]).validate();
  });
}
