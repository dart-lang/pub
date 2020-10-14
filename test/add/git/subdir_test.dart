// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from git subdirectory', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.dir('subdir', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
    ]);

    await repo.create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['sub', '--git-url', '../foo.git', '--git-path', 'subdir']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('subdir', [d.libDir('sub', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackagesFile({
      'sub': pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir')
    }).validate();

    await d.appDir({
      'sub': {
        'git': {'url': '../foo.git', 'path': 'subdir'}
      }
    }).validate();
  });

  test('adds a package in a deep subdirectory', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.dir('sub', [
        d.dir('dir', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
      ])
    ]);
    await repo.create();

    await d.appDir({}).create();

    await pubAdd(
        args: ['sub', '--git-url', '../foo.git', '--git-path', 'sub/dir']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('sub', [
            d.dir('dir', [d.libDir('sub', '1.0.0')])
          ])
        ])
      ])
    ]).validate();

    await d.appPackagesFile({
      'sub': pathInCache('git/foo-${await repo.revParse('HEAD')}/sub/dir')
    }).validate();

    await d.appDir({
      'sub': {
        'git': {'url': '../foo.git', 'path': 'sub/dir'}
      }
    }).validate();
  });
}
