// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Skip()

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test("upgrades one locked Git package but no others", () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.git(
        'bar.git', [d.libDir('bar'), d.libPubspec('bar', '1.0.0')]).create();

    await d.appDir({
      "foo": {"git": "../foo.git"},
      "bar": {"git": "../bar.git"}
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubGet(args: ['--packages-dir']);

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')]),
      d.dir('bar', [d.file('bar.dart', 'main() => "bar";')])
    ]).validate();

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await d.git('bar.git',
        [d.libDir('bar', 'bar 2'), d.libPubspec('bar', '1.0.0')]).commit();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubUpgrade(args: ['--packages-dir', 'foo']);

    await d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo 2";')]),
      d.dir('bar', [d.file('bar.dart', 'main() => "bar";')])
    ]).validate();
  });
}
