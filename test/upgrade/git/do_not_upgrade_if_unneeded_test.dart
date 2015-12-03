// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_tests;

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

    pubGet();

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

    pubUpgrade(args: ['foo']);

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
