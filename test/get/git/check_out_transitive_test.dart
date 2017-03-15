// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('checks out packages transitively from Git', () {
    ensureGit();

    d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0', deps: {
        "bar": {"git": "../bar.git"}
      })
    ]).create();

    d.git('bar.git', [d.libDir('bar'), d.libPubspec('bar', '1.0.0')]).create();

    d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache',
            [d.gitPackageRepoCacheDir('foo'), d.gitPackageRepoCacheDir('bar')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('bar')
      ])
    ]).validate();

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')]),
      d.dir('bar', [d.file('bar.dart', 'main() => "bar";')])
    ]).validate();
  });
}
