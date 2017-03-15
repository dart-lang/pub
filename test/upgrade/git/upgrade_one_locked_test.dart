// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("upgrades one locked Git package but no others", () {
    ensureGit();

    d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    d.git('bar.git', [d.libDir('bar'), d.libPubspec('bar', '1.0.0')]).create();

    d.appDir({
      "foo": {"git": "../foo.git"},
      "bar": {"git": "../bar.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ['--packages-dir']);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')]),
      d.dir('bar', [d.file('bar.dart', 'main() => "bar";')])
    ]).validate();

    d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    d.git('bar.git',
        [d.libDir('bar', 'bar 2'), d.libPubspec('bar', '1.0.0')]).commit();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubUpgrade(args: ['--packages-dir', 'foo']);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 2";')]),
      d.dir('bar', [d.file('bar.dart', 'main() => "bar";')])
    ]).validate();
  });
}
