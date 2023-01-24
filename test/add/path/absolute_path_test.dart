// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('path dependency with absolute path', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir(dependencies: {}).create();

    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(args: ['foo', '--path', absolutePath]);

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', path: absolutePath),
    ]).validate();

    await d.appDir(
      dependencies: {
        'foo': {'path': absolutePath}
      },
    ).validate();
  });

  test('adds a package from absolute path with version constraint', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir(dependencies: {}).create();
    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(args: ['foo:0.0.1', '--path', absolutePath]);

    await d.appDir(
      dependencies: {
        'foo': {'path': absolutePath, 'version': '0.0.1'}
      },
    ).validate();
  });

  test('fails when adding multiple packages through local path', () async {
    ensureGit();

    await d.git(
      'foo.git',
      [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
    ).create();

    await d.appDir(dependencies: {}).create();
    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(
      args: ['foo:2.0.0', 'bar:0.1.3', 'baz:1.3.1', '--path', absolutePath],
      error: contains('--path cannot be used with multiple packages.'),
      exitCode: exit_codes.USAGE,
    );

    await d.appDir(dependencies: {}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('fails when adding with an invalid version constraint', () async {
    ensureGit();

    await d.git(
      'foo.git',
      [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
    ).create();

    await d.appDir(dependencies: {}).create();
    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(
      args: ['foo:2.0.0', '--path', absolutePath],
      error: equalsIgnoringWhitespace(
          'Because myapp depends on foo from path which doesn\'t exist '
          '(could not find package foo at "$absolutePath"), version solving '
          'failed.'),
      exitCode: exit_codes.DATA,
    );

    await d.appDir(dependencies: {}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('fails if path does not exist', () async {
    await d.appDir(dependencies: {}).create();

    final absolutePath = path.join(d.sandbox, 'foo');

    await pubAdd(
      args: ['foo', '--path', absolutePath],
      error: equalsIgnoringWhitespace(
          'Because myapp depends on foo from path which doesn\'t exist '
          '(could not find package foo at "$absolutePath"), version solving '
          'failed.'),
      exitCode: exit_codes.DATA,
    );

    await d.appDir(dependencies: {}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('can be overriden by dependency override', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.2');
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {},
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).create();

    final absolutePath = path.join(d.sandbox, 'foo');
    await pubAdd(args: ['foo', '--path', absolutePath]);

    await d.cacheDir({'foo': '1.2.2'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.2'),
    ]).validate();
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'path': absolutePath}
        },
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).validate();
  });
}
