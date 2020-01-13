// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades Git packages to an incompatible pubspec', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
        ]),
        d.gitPackageRevisionCacheDir('foo'),
      ])
    ]).validate();

    var originalFooSpec = packageSpecLine('foo');

    await d.git(
        'foo.git', [d.libDir('zoo'), d.libPubspec('zoo', '1.0.0')]).commit();

    await pubUpgrade(
        error: contains('"name" field doesn\'t match expected name "foo".'),
        exitCode: exit_codes.DATA);

    expect(packageSpecLine('foo'), originalFooSpec);
  });
}
