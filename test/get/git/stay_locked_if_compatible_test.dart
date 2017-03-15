// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration(
      "doesn't upgrade a locked Git package with a new compatible "
      "constraint", () {
    ensureGit();

    d.git('foo.git',
        [d.libDir('foo', 'foo 1.0.0'), d.libPubspec("foo", "1.0.0")]).create();

    d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 1.0.0";')])
    ]).validate();

    d.git('foo.git',
        [d.libDir('foo', 'foo 1.0.1'), d.libPubspec("foo", "1.0.1")]).commit();

    d.appDir({
      "foo": {"git": "../foo.git", "version": ">=1.0.0"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 1.0.0";')])
    ]).validate();
  });
}
