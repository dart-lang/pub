// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  group('pub upgrade --major-versions', () {
    test('bumps dependency constraints and shows summary report', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('bar', '0.1.0')
        ..serve('bar', '0.2.0')
        ..serve('baz', '1.0.0')
        ..serve('baz', '1.0.1');

      await d
          .appDir(
            dependencies: {'foo': '^1.0.0', 'bar': '^0.1.0', 'baz': '^1.0.0'},
          )
          .create();

      await pubGet();

      // 2 constraints should be updated
      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^0.1.0 -> ^0.2.0'),
        ]),
      );

      await d
          .appDir(
            dependencies: {'foo': '^2.0.0', 'bar': '^0.2.0', 'baz': '^1.0.0'},
          )
          .validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
        d.packageConfigEntry(name: 'bar', version: '0.2.0'),
        d.packageConfigEntry(name: 'baz', version: '1.0.1'),
      ]).validate();
    });

    test('bumps dev_dependency constraints and shows summary report', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('bar', '0.1.0')
        ..serve('bar', '0.2.0')
        ..serve('baz', '1.0.0')
        ..serve('baz', '1.0.1');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'foo': '^1.0.0',
            'bar': '^0.1.0',
            'baz': '^1.0.0',
          },
        }),
      ]).create();

      await pubGet();

      // 2 constraints should be updated
      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^0.1.0 -> ^0.2.0'),
        ]),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'foo': '^2.0.0', // bumped
            'bar': '^0.2.0', // bumped
            'baz': '^1.0.0',
          },
        }),
      ]).validate();

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
        d.packageConfigEntry(name: 'bar', version: '0.2.0'),
        d.packageConfigEntry(name: 'baz', version: '1.0.1'),
      ]).validate();
    });

    test('upgrades only the selected package', () async {
      final server =
          await servePackages()
            ..serve('foo', '1.0.0')
            ..serve('foo', '2.0.0')
            ..serve('bar', '0.1.0');

      await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^0.1.0'}).create();

      await pubGet();

      server.serve('bar', '0.1.1');

      // 1 constraint should be updated
      await pubUpgrade(
        args: ['--major-versions', 'foo'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
        ]),
      );

      await d
          .appDir(
            dependencies: {
              'foo': '^2.0.0', // bumped
              'bar': '^0.1.0',
            },
          )
          .validate();

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
        d.packageConfigEntry(name: 'bar', version: '0.1.0'),
      ]).validate();
    });

    test('chooses the latest version where possible', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('foo', '3.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet();

      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^3.0.0'),
        ]),
      );

      await d.dir(appPath, [
        // The pubspec file should be modified.
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^3.0.0'},
        }),
        // The lockfile should be modified.
        d.file('pubspec.lock', contains('3.0.0')),
      ]).validate();

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '3.0.0'),
      ]).validate();
    });

    test('overridden dependencies - no resolution', () async {
      await servePackages()
        ..serve('foo', '1.0.0', deps: {'bar': '^2.0.0'})
        ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
        ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
        ..serve('bar', '2.0.0', deps: {'foo': '^2.0.0'});

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.1',
          'dependencies': {'foo': 'any', 'bar': 'any'},
          'dependency_overrides': {'foo': '1.0.0', 'bar': '1.0.0'},
        }),
      ]).create();

      await pubGet();

      await pubUpgrade(
        args: ['--major-versions'],
        output: contains('No changes to pubspec.yaml!'),
        warning: allOf([
          contains('Warning: dependency_overrides prevents upgrades for: '),
          contains('foo'), // ordering not ensured
          contains('bar'),
        ]),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.1',
          'dependencies': {'foo': 'any', 'bar': 'any'},
          'dependency_overrides': {'foo': '1.0.0', 'bar': '1.0.0'},
        }),
      ]).validate();

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.0.0'),
        d.packageConfigEntry(name: 'bar', version: '1.0.0'),
      ]).validate();
    });

    test('upgrade should not downgrade any versions', () async {
      /// The version solver solves the packages with the least number of
      /// versions remaining, so we add more 'bar' packages to force 'foo' to be
      /// resolved first
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve(
          'foo',
          '2.0.0',
          pubspec: {
            'dependencies': {'bar': '1.0.0'},
          },
        )
        ..serve('bar', '1.0.0')
        ..serve('bar', '2.0.0')
        ..serve('bar', '3.0.0')
        ..serve('bar', '4.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^2.0.0'}).create();

      await pubGet();

      // 1 constraint should be updated
      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('bar: ^2.0.0 -> ^4.0.0'),
        ]),
      );

      await d
          .appDir(dependencies: {'foo': '^1.0.0', 'bar': '^4.0.0'})
          .validate();

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.0.0'),
        d.packageConfigEntry(name: 'bar', version: '4.0.0'),
      ]).validate();
    });

    test('should take pubspec_overrides.yaml into account', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0');
      await d.dir('bar', [d.libPubspec('bar', '1.0.0')]).create();
      await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^1.0.0'}).create();
      await d.dir(appPath, [
        d.pubspecOverrides({
          'dependency_overrides': {
            'bar': {'path': '../bar'},
          },
        }),
      ]).create();

      await pubGet();

      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
        ]),
      );
    });

    test('works with an explicit "hosted" description:', () async {
      await servePackages();
      final alternativeServer = await startPackageServer();
      alternativeServer.serve('foo', '1.0.0');
      alternativeServer.serve('foo', '2.0.0');
      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': alternativeServer.url, 'version': '^1.0.0'},
            },
          )
          .create();

      await pubGet();

      await pubUpgrade(
        args: ['--major-versions'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
        ]),
      );
      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': alternativeServer.url, 'version': '^2.0.0'},
            },
          )
          .validate();
    });
  });
}
