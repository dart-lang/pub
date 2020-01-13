// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('depends on a package in a subdirectory', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('subdir', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
    ]);
    await repo.create();

    await d.appDir({
      'sub': {
        'git': {'url': '../foo.git', 'path': 'subdir'}
      }
    }).create();

    await pubGet();

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
  });

  test('depends on a package in a deep subdirectory', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('sub', [
        d.dir('dir', [d.libPubspec('sub', '1.0.0'), d.libDir('sub', '1.0.0')])
      ])
    ]);
    await repo.create();

    await d.appDir({
      'sub': {
        'git': {'url': '../foo.git', 'path': 'sub/dir'}
      }
    }).create();

    await pubGet();

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
  });

  test('depends on multiple packages in subdirectories', () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir('subdir1',
          [d.libPubspec('sub1', '1.0.0'), d.libDir('sub1', '1.0.0')]),
      d.dir(
          'subdir2', [d.libPubspec('sub2', '1.0.0'), d.libDir('sub2', '1.0.0')])
    ]);
    await repo.create();

    await d.appDir({
      'sub1': {
        'git': {'url': '../foo.git', 'path': 'subdir1'}
      },
      'sub2': {
        'git': {'url': '../foo.git', 'path': 'subdir2'}
      }
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.hashDir('foo', [
          d.dir('subdir1', [d.libDir('sub1', '1.0.0')]),
          d.dir('subdir2', [d.libDir('sub2', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackagesFile({
      'sub1': pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir1'),
      'sub2': pathInCache('git/foo-${await repo.revParse('HEAD')}/subdir2')
    }).validate();
  });

  test('depends on packages in the same subdirectory at different revisions',
      () async {
    ensureGit();

    var repo = d.git('foo.git', [
      d.dir(
          'subdir', [d.libPubspec('sub1', '1.0.0'), d.libDir('sub1', '1.0.0')])
    ]);
    await repo.create();
    var oldRevision = await repo.revParse('HEAD');

    deleteEntry(p.join(d.sandbox, 'foo.git', 'subdir'));

    await d.git('foo.git', [
      d.dir(
          'subdir', [d.libPubspec('sub2', '1.0.0'), d.libDir('sub2', '1.0.0')])
    ]).commit();
    var newRevision = await repo.revParse('HEAD');

    await d.appDir({
      'sub1': {
        'git': {'url': '../foo.git', 'path': 'subdir', 'ref': oldRevision}
      },
      'sub2': {
        'git': {'url': '../foo.git', 'path': 'subdir'}
      }
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.dir('foo-$oldRevision', [
          d.dir('subdir', [d.libDir('sub1', '1.0.0')])
        ]),
        d.dir('foo-$newRevision', [
          d.dir('subdir', [d.libDir('sub2', '1.0.0')])
        ])
      ])
    ]).validate();

    await d.appPackagesFile({
      'sub1': pathInCache('git/foo-$oldRevision/subdir'),
      'sub2': pathInCache('git/foo-$newRevision/subdir')
    }).validate();
  });
}
