// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('allows empty version constraint', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({}).create();

    await pubAdd(args: ['foo']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({'foo': '^1.2.3'}).validate();
  });

  test('allows specific version constraint', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({}).create();

    await pubAdd(args: ['foo:1.2.3']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({'foo': '1.2.3'}).validate();
  });

  test('allows the "any" version constraint', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({}).create();

    await pubAdd(args: ['foo:any']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({'foo': 'any'}).validate();
  });

  test('allows version constraint range', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({}).create();

    await pubAdd(args: ['foo:>1.2.0 <2.0.0']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({'foo': '>1.2.0 <2.0.0'}).validate();
  });

  group('does not update pubspec if no available version found', () {
    test('simple', () async {
      await servePackages((builder) => builder.serve('foo', '1.0.3'));

      await d.appDir({}).create();

      await pubAdd(
          args: ['foo:>1.2.0 <2.0.0'],
          error: contains(
              "Because myapp depends on foo >1.2.0 <2.0.0 which doesn't "
              'match any versions, version solving failed.'));

      await d.appDir({}).validate();
      await d.dir(appPath, [
        // The lockfile should not be created.
        d.nothing('pubspec.lock'),
        // The "packages" directory should not have been generated.
        d.nothing('packages'),
        // The ".packages" file should not have been created.
        d.nothing('.packages'),
      ]).validate();
    });

    test('transitive', () async {
      await servePackages((builder) {
        builder.serve('foo', '1.2.3', deps: {'bar': '2.0.4'});
        builder.serve('bar', '2.0.3');
        builder.serve('bar', '2.0.4');
      });

      await d.appDir({'bar': '2.0.3'}).create();

      await pubAdd(
          args: ['foo:1.2.3'],
          error: contains(
              'Because every version of foo depends on bar 2.0.4 and myapp '
              'depends on bar 2.0.3, foo is forbidden.'));

      await d.appDir({'bar': '2.0.3'}).validate();
      await d.dir(appPath, [
        // The lockfile should not be created.
        d.nothing('pubspec.lock'),
        // The "packages" directory should not have been generated.
        d.nothing('packages'),
        // The ".packages" file should not have been created.
        d.nothing('.packages'),
      ]).validate();
    });
  });
}
