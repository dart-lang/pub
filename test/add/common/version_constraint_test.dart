// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('allows empty version constraint', () async {
    await servePackages()
      ..serve('foo', '0.2.3')
      ..serve('foo', '1.0.1')
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.0.0-dev')
      ..serve('foo', '1.3.4-dev');

    await d.appDir(dependencies: {}).create();

    await pubAdd(args: ['foo']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
    await d.appDir(dependencies: {'foo': '^1.2.3'}).validate();
  });

  test('allows specific version constraint', () async {
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

  test('allows specific pre-release version constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3-dev');

    await d.appDir(dependencies: {}).create();

    await pubAdd(args: ['foo:1.2.3-dev']);

    await d.cacheDir({'foo': '1.2.3-dev'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3-dev'),
    ]).validate();
    await d.appDir(dependencies: {'foo': '1.2.3-dev'}).validate();
  });

  test('allows the "any" version constraint', () async {
    await servePackages()
      ..serve('foo', '0.2.3')
      ..serve('foo', '1.0.1')
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.0.0-dev')
      ..serve('foo', '1.3.4-dev');

    await d.appDir(dependencies: {}).create();

    await pubAdd(args: ['foo:any']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
    await d.appDir(dependencies: {'foo': 'any'}).validate();
  });

  test('allows version constraint range', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {}).create();

    await pubAdd(args: ['foo:>1.2.0 <2.0.0']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
    ]).validate();
    await d.appDir(dependencies: {'foo': '>1.2.0 <2.0.0'}).validate();
  });

  test(
      'empty constraint allows it to choose the latest version not in conflict',
      () async {
    await servePackages()
      ..serve('foo', '0.1.0')
      ..serve('foo', '1.2.3', deps: {'bar': '2.0.4'})
      ..serve('bar', '2.0.3')
      ..serve('bar', '2.0.4');

    await d.appDir(dependencies: {'bar': '2.0.3'}).create();

    await pubAdd(args: ['foo']);

    await d.appDir(dependencies: {'foo': '^0.1.0', 'bar': '2.0.3'}).validate();

    await d.cacheDir({'foo': '0.1.0', 'bar': '2.0.3'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '0.1.0'),
      d.packageConfigEntry(name: 'bar', version: '2.0.3'),
    ]).validate();
  });

  group('does not update pubspec if no available version found', () {
    test('simple', () async {
      final server = await servePackages();
      server.serve('foo', '1.0.3');

      await d.appDir(dependencies: {}).create();

      await pubAdd(
        args: ['foo:>1.2.0 <2.0.0'],
        error:
            contains("Because myapp depends on foo >1.2.0 <2.0.0 which doesn't "
                'match any versions, version solving failed.'),
        exitCode: exit_codes.DATA,
      );

      await d.appDir(dependencies: {}).validate();
      await d.dir(appPath, [
        // The lockfile should not be created.
        d.nothing('pubspec.lock'),
        // The ".packages" file should not have been created.
        d.nothing('.packages'),
      ]).validate();
    });

    test('transitive', () async {
      await servePackages()
        ..serve('foo', '1.2.3', deps: {'bar': '2.0.4'})
        ..serve('bar', '2.0.3')
        ..serve('bar', '2.0.4');

      await d.appDir(dependencies: {'bar': '2.0.3'}).create();

      await pubAdd(
        args: ['foo:1.2.3'],
        error: contains(
            'Because every version of foo depends on bar 2.0.4 and myapp '
            'depends on bar 2.0.3, foo is forbidden.'),
        exitCode: exit_codes.DATA,
      );

      await d.appDir(dependencies: {'bar': '2.0.3'}).validate();
      await d.dir(appPath, [
        // The lockfile should not be created.
        d.nothing('pubspec.lock'),
        // The ".packages" file should not have been created.
        d.nothing('.packages'),
      ]).validate();
    });
  });
}
