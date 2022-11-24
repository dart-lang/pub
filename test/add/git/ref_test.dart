// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from git with ref', () async {
    ensureGit();

    final repo = d.git(
        'foo.git', [d.libDir('foo', 'foo 1'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    await repo.runGit(['branch', 'old']);

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await d.appDir({}).create();

    await pubAdd(args: ['foo', '--git-url', '../foo.git', '--git-ref', 'old']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
        ]),
        d.gitPackageRevisionCacheDir('foo', modifier: 1),
      ])
    ]).validate();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'ref': 'old'}
      }
    }).validate();
  });

  test('fails when adding from an invalid ref', () async {
    ensureGit();

    final repo = d.git(
        'foo.git', [d.libDir('foo', 'foo 1'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    await repo.runGit(['branch', 'new']);

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await d.appDir({}).create();

    await pubAdd(
        args: ['foo', '--git-url', '../foo.git', '--git-ref', 'old'],
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
}
