// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test('checks out and upgrades a package from Git', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubGet(args: ["--packages-dir"]);

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')])
    ]).validate();

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubUpgrade(
        args: ["--packages-dir"], output: contains("Changed 1 dependency!"));

    // When we download a new version of the git package, we should re-use the
    // git/cache directory but create a new git/ directory.
    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('foo', 2)
      ])
    ]).validate();

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 2";')])
    ]).validate();
  });
}
