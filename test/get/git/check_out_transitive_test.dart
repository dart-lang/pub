// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('checks out packages transitively from Git', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0', deps: {
        'bar': {'git': '../bar.git'}
      })
    ]).create();

    await d.git(
        'bar.git', [d.libDir('bar'), d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache',
            [d.gitPackageRepoCacheDir('foo'), d.gitPackageRepoCacheDir('bar')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('bar')
      ])
    ]).validate();

    expect(packageSpecLine('foo'), isNotNull);
    expect(packageSpecLine('bar'), isNotNull);
  });
}
