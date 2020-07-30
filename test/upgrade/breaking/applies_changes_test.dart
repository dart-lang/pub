// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  group('--breaking', () {
    test('applies breaking changes and shows summary report', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0');
        builder.serve('bar', '0.1.0');
        builder.serve('bar', '0.2.0');
        builder.serve('baz', '1.0.0');
        builder.serve('baz', '1.0.1');
      });

      // Create the lockfile.
      await d
          .appDir({'foo': '^1.0.0', 'bar': '^0.1.0', 'baz': '^1.0.0'}).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d
          .appDir({'foo': '^1.0.0', 'bar': '^0.1.0', 'baz': '^1.0.0'}).create();

      // Only two breaking changes should be detected.
      await pubUpgrade(
          args: ['--breaking'],
          output: allOf([
            contains('Detected 2 potential breaking changes:'),
            contains('foo: ^1.0.0 -> ^2.0.0'),
            contains('bar: ^0.1.0 -> ^0.2.0')
          ]));

      await d.appDir(
          {'foo': '^2.0.0', 'bar': '^0.2.0', 'baz': '^1.0.0'}).validate();

      await d.appPackagesFile(
          {'foo': '2.0.0', 'bar': '0.2.0', 'baz': '1.0.1'}).validate();
    });
    test(
        'applies breaking changes and shows summary report for dev dependencies',
        () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0');
        builder.serve('bar', '0.1.0');
        builder.serve('bar', '0.2.0');
        builder.serve('baz', '1.0.0');
        builder.serve('baz', '1.0.1');
      });

      // Create the lockfile.
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'foo': '^1.0.0',
            'bar': '^0.1.0',
            'baz': '^1.0.0'
          }
        })
      ]).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'foo': '^1.0.0',
            'bar': '^0.1.0',
            'baz': '^1.0.0'
          }
        })
      ]).create();

      // Only two breaking changes should be detected.
      await pubUpgrade(
          args: ['--breaking'],
          output: allOf([
            contains('Detected 2 potential breaking changes:'),
            contains('foo: ^1.0.0 -> ^2.0.0'),
            contains('bar: ^0.1.0 -> ^0.2.0')
          ]));

      await d.dir(appPath, [
        // The pubspec file should be modified.
        d.pubspec({
          'name': 'myapp',
          'dev_dependencies': {
            'foo': '^2.0.0',
            'bar': '^0.2.0',
            'baz': '^1.0.0'
          }
        }),
      ]).validate();

      await d.appPackagesFile(
          {'foo': '2.0.0', 'bar': '0.2.0', 'baz': '1.0.1'}).validate();
    });

    test('upgrades only a selected package', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0');
        builder.serve('bar', '0.1.0');
        builder.serve('bar', '0.2.0');
      });

      // Create the lockfile.
      await d.appDir({'foo': '^1.0.0', 'bar': '^0.1.0'}).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d.appDir({'foo': '^1.0.0', 'bar': '^0.1.0'}).create();

      // Only one breaking changes should be detected.
      await pubUpgrade(
          args: ['--breaking', 'foo'],
          output: allOf([
            contains('Detected 1 potential breaking change:'),
            contains('foo: ^1.0.0 -> ^2.0.0'),
          ]));

      await d.dir(appPath, [
        // The pubspec file should be modified.
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^2.0.0', 'bar': '^0.1.0'}
        }),
      ]).validate();

      await d.appPackagesFile({'foo': '2.0.0', 'bar': '0.1.0'}).validate();
    });

    test('chooses the latest version where possible', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0');
        builder.serve('foo', '3.0.0');
      });

      // Create the lockfile.
      await d.appDir({'foo': '1.0.0'}).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d.appDir({'foo': '1.0.0'}).create();

      await pubUpgrade(
          args: ['--breaking'],
          output: allOf([
            contains('Detected 1 potential breaking change:'),
            contains('foo: 1.0.0 -> ^3.0.0')
          ]));

      await d.dir(appPath, [
        // The pubspec file should be modified.
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '^3.0.0'}
        }),
        // The lockfile should be modified.
        d.file('pubspec.lock', contains('3.0.0'))
      ]).validate();

      await d.appPackagesFile({'foo': '3.0.0'}).validate();
    });

    test('overridden dependencies - no resolution', () async {
      ensureGit();
      await servePackages(
        (builder) => builder
          ..serve('foo', '1.0.0', deps: {'bar': '^2.0.0'})
          ..serve('foo', '2.0.0', deps: {'bar': '^1.0.0'})
          ..serve('bar', '1.0.0', deps: {'foo': '^1.0.0'})
          ..serve('bar', '2.0.0', deps: {'foo': '^2.0.0'}),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'app',
          'version': '1.0.1',
          'dependencies': {
            'foo': 'any',
            'bar': 'any',
          },
          'dependency_overrides': {
            'foo': '1.0.0',
            'bar': '1.0.0',
          },
        })
      ]).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.1',
          'dependencies': {
            'foo': 'any',
            'bar': 'any',
          },
          'dependency_overrides': {
            'foo': '1.0.0',
            'bar': '1.0.0',
          },
        })
      ]).create();

      await pubUpgrade(
          args: ['--breaking'],
          output: contains('No breaking changes detected!'));

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.0.1',
          'dependencies': {
            'foo': 'any',
            'bar': 'any',
          },
          'dependency_overrides': {
            'foo': '1.0.0',
            'bar': '1.0.0',
          },
        })
      ]).validate();

      await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.0.0'}).validate();
    });

    test('upgrade should not downgrade any versions', () async {
      /// The version solver solves the packages with the least number of
      /// versions remaining, so we add more 'bar' packages to force 'foo' to be
      /// resolved first
      await servePackages((builder) {
        builder.serve('foo', '1.0.0');
        builder.serve('foo', '2.0.0', pubspec: {
          'dependencies': {'bar': '1.0.0'}
        });
        builder.serve('bar', '1.0.0');
        builder.serve('bar', '2.0.0');
        builder.serve('bar', '3.0.0');
        builder.serve('bar', '4.0.0');
      });

      // Create the lockfile.
      await d.appDir({'foo': '^1.0.0', 'bar': '2.0.0'}).create();

      await pubGet();

      // Recreating the appdir because the previous one only lasts for one
      // command.
      await d.appDir({'foo': '^1.0.0', 'bar': '2.0.0'}).create();

      // Only two breaking changes should be detected.
      await pubUpgrade(
          args: ['--breaking'], output: contains('No breaking changes deasda'));

      await d.appDir({'foo': '^1.0.0', 'bar': '^2.0.0'}).validate();

      await d.appPackagesFile({'foo': '^1.0.0', 'bar': '^2.0.0'}).validate();
    });
  });
}
