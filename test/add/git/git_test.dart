// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from git', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({}).create();

    await pubAdd(args: ['foo', '--git-url', '../foo.git']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).validate();
  });

  test('adds a package from git with version constraint', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({}).create();

    await pubAdd(args: ['foo:1.0.0', '--git-url', '../foo.git']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    await d.appDir({
      'foo': {'git': '../foo.git', 'version': '1.0.0'}
    }).validate();
  });

  test('fails when adding with an invalid version constraint', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo:2.0.0', '--git-url', '../foo.git'],
        error: equalsIgnoringWhitespace(
            'Because myapp depends on foo 2.0.0 from git which doesn\'t match '
            'any versions, version solving failed.'),
        exitCode: exit_codes.DATA);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('fails when adding from an invalid url', () async {
    ensureGit();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--git-url', '../foo.git'],
        error: contains('Unable to resolve package "foo" with the given '
            'git parameters'),
        exitCode: exit_codes.DATA);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('fails if git-url is not declared', () async {
    ensureGit();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--git-ref', 'master'],
        error: contains('The `--git-url` is required for git dependencies.'),
        exitCode: exit_codes.USAGE);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('can be overriden by dependency override', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.2');
    });

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {},
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).create();

    await pubAdd(args: ['foo', '--git-url', '../foo.git']);

    await d.cacheDir({'foo': '1.2.2'}).validate();
    await d.appPackagesFile({'foo': '1.2.2'}).validate();
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'git': '../foo.git'}
        },
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).validate();
  });
}
