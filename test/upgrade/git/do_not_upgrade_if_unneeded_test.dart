// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      "doesn't upgrade one locked Git package's dependencies if it's "
      'not necessary', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0', deps: {
        'foo_dep': {'git': '../foo_dep.git'}
      })
    ]).create();

    await d.git('foo_dep.git',
        [d.libDir('foo_dep'), d.libPubspec('foo_dep', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
          d.gitPackageRepoCacheDir('foo_dep')
        ]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('foo_dep'),
      ])
    ]).validate();

    var originalFooDepSpec = packageSpecLine('foo_dep');

    await d.git('foo.git', [
      d.libDir('foo', 'foo 2'),
      d.libPubspec('foo', '1.0.0', deps: {
        'foo_dep': {'git': '../foo_dep.git'}
      })
    ]).create();

    await d.git('foo_dep.git', [
      d.libDir('foo_dep', 'foo_dep 2'),
      d.libPubspec('foo_dep', '1.0.0')
    ]).commit();

    await pubUpgrade(args: ['foo']);

    await d.dir(cachePath, [
      d.dir('git', [
        d.gitPackageRevisionCacheDir('foo', 2),
      ])
    ]).validate();

    expect(packageSpecLine('foo_dep'), originalFooDepSpec);
  });
}
