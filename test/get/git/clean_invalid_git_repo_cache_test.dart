// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

/// Invalidates a git clone in the pub-cache, by recreating it as empty-directory.
void _invalidateGitCache(String repo) {
  final cacheDir =
      path.join(d.sandbox, path.joinAll([cachePath, 'git', 'cache']));
  final Directory fooCacheDir =
      Directory(cacheDir).listSync().firstWhere((entity) {
    return entity is Directory &&
        entity.path.split(Platform.pathSeparator).last.startsWith(repo);
  });

  fooCacheDir.deleteSync(recursive: true);
  fooCacheDir.createSync();
}

void main() {
  test('Clean-up invalid git repo cache', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    _invalidateGitCache('foo');

    await pubGet();
  });

  test('Clean-up invalid git repo cache at a specific branch', () async {
    ensureGit();

    var repo =
        d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    await repo.runGit(['branch', 'old']);

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'ref': 'old'}
      }
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    _invalidateGitCache('foo');

    await pubGet();
  });

  test('Clean-up invalid git repo cache at a specific commit', () async {
    ensureGit();

    var repo =
        d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    var commit = await repo.revParse('HEAD');

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'ref': commit}
      }
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    _invalidateGitCache('foo');

    await pubGet();
  });
}
