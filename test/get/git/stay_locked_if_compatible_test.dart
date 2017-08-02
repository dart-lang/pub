// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test(
      "doesn't upgrade a locked Git package with a new compatible "
      "constraint", () async {
    ensureGit();

    await d.git('foo.git',
        [d.libDir('foo', 'foo 1.0.0'), d.libPubspec("foo", "1.0.0")]).create();

    await d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubGet(args: ["--packages-dir"]);

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 1.0.0";')])
    ]).validate();

    await d.git('foo.git',
        [d.libDir('foo', 'foo 1.0.1'), d.libPubspec("foo", "1.0.1")]).commit();

    await d.appDir({
      "foo": {"git": "../foo.git", "version": ">=1.0.0"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubGet(args: ["--packages-dir"]);

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 1.0.0";')])
    ]).validate();
  });
}
