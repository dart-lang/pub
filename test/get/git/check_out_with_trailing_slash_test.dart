// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  group('(regression)', () {
    test('checks out a package from Git with a trailing slash', () async {
      ensureGit();

      await d.git(
          'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

      await d.appDir({
        'foo': {'git': '../foo.git/'}
      }).create();

      await pubGet();

      await d.dir(cachePath, [
        d.dir('git', [
          d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
          d.gitPackageRevisionCacheDir('foo')
        ])
      ]).validate();

      await d.dir(cachePath, [
        d.dir('git', [
          d.dir('cache', [
            d.gitPackageRepoCacheDir('foo'),
          ]),
          d.gitPackageRevisionCacheDir('foo'),
        ])
      ]).validate();
    });
  });
}
