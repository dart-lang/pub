// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('checks out a package at a specific branch from Git', () async {
    ensureGit();

    var repo = d.git(
        'foo.git', [d.libDir('foo', 'foo 1'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    await repo.runGit(['branch', 'old']);

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'ref': 'old'}
      }
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
        ]),
        d.gitPackageRevisionCacheDir('foo', 1),
      ])
    ]).validate();
  });
}
