// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('can use relative path', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({}).create();

    await pubAdd(args: ['foo', '--path', '../foo']);

    await d.appPackagesFile({'foo': '../foo'}).validate();

    await d.appDir({
      'foo': {'path': '../foo'}
    }).validate();
  });

  test('fails if path does not exist', () async {
    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--path', '../foo'],
        error: equalsIgnoringWhitespace(
            'Because myapp depends on foo from path which doesn\'t exist '
            '(could not find package foo at "..${Platform.pathSeparator}foo"), '
            'version solving failed.'),
        exitCode: exit_codes.DATA);

    await d.appDir({}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test('adds a package from absolute path with version constraint', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({}).create();

    await pubAdd(args: ['foo:0.0.1', '--path', '../foo']);

    await d.appDir({
      'foo': {'path': '../foo', 'version': '0.0.1'}
    }).validate();
  });

  test('fails when adding with an invalid version constraint', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo:2.0.0', '--path', '../foo'],
        error: equalsIgnoringWhitespace(
            'Because myapp depends on foo from path which doesn\'t exist '
            '(could not find package foo at "..${Platform.pathSeparator}foo"), '
            'version solving failed.'),
        exitCode: exit_codes.DATA);

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
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {},
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).create();

    await pubAdd(args: ['foo', '--path', '../foo']);

    await d.cacheDir({'foo': '1.2.2'}).validate();
    await d.appPackagesFile({'foo': '1.2.2'}).validate();
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'path': '../foo'}
        },
        'dependency_overrides': {'foo': '1.2.2'}
      })
    ]).validate();
  });
}
