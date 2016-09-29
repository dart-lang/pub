// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("doesn't upgrade one locked Git package's dependencies if it's "
      "not necessary", () {
    ensureGit();

    d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec("foo", "1.0.0", deps: {
        "foo_dep": {"git": "../foo_dep.git"
      }})
    ]).create();

    d.git('foo_dep.git', [
      d.libDir('foo_dep'),
      d.libPubspec('foo_dep', '1.0.0')
    ]).create();

    d.appDir({"foo": {"git": "../foo.git"}}).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(packagesPath, [
      d.dir('foo', [
        d.file('foo.dart', 'main() => "foo";')
      ]),
      d.dir('foo_dep', [
        d.file('foo_dep.dart', 'main() => "foo_dep";')
      ])
    ]).validate();

    d.git('foo.git', [
      d.libDir('foo', 'foo 2'),
      d.libPubspec("foo", "1.0.0", deps: {
        "foo_dep": {"git": "../foo_dep.git"}
      })
    ]).create();

    d.git('foo_dep.git', [
      d.libDir('foo_dep', 'foo_dep 2'),
      d.libPubspec('foo_dep', '1.0.0')
    ]).commit();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubUpgrade(args: ["--packages-dir", 'foo']);

    d.dir(packagesPath, [
      d.dir('foo', [
        d.file('foo.dart', 'main() => "foo 2";')
      ]),
      d.dir('foo_dep', [
        d.file('foo_dep.dart', 'main() => "foo_dep";')
      ]),
    ]).validate();
  });
}
