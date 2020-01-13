// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades locked Git packages', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.git(
        'bar.git', [d.libDir('bar'), d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'},
      'bar': {'git': '../bar.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache',
            [d.gitPackageRepoCacheDir('foo'), d.gitPackageRepoCacheDir('bar')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('bar'),
      ])
    ]).validate();

    var originalFooSpec = packageSpecLine('foo');
    var originalBarSpec = packageSpecLine('bar');

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await d.git('bar.git',
        [d.libDir('bar', 'bar 2'), d.libPubspec('bar', '1.0.0')]).commit();

    await pubUpgrade();

    await d.dir(cachePath, [
      d.dir('git', [
        d.gitPackageRevisionCacheDir('foo', 2),
        d.gitPackageRevisionCacheDir('bar', 2),
      ])
    ]).validate();

    expect(packageSpecLine('foo'), isNot(originalFooSpec));
    expect(packageSpecLine('bar'), isNot(originalBarSpec));
  });
}
