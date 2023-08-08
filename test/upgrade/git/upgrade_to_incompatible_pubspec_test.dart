// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades Git packages to an incompatible pubspec', () async {
    ensureGit();

    await d.git(
      'foo.git',
      [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
    ).create();

    await d.appDir(
      dependencies: {
        'foo': {'git': '../foo.git'},
      },
    ).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
        ]),
        d.gitPackageRevisionCacheDir('foo'),
      ]),
    ]).validate();

    var originalFooSpec = packageSpec('foo');

    await d.git(
      'foo.git',
      [d.libDir('zoo'), d.libPubspec('zoo', '1.0.0')],
    ).commit();

    await pubUpgrade(
      error: contains('Expected to find package "foo", found package "zoo".'),
      exitCode: exit_codes.DATA,
    );

    expect(packageSpec('foo'), originalFooSpec);
  });
}
