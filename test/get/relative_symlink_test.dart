// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Pub uses NTFS junction points to create links in the packages directory.
// These (unlike the symlinks that are supported in Vista and later) do not
// support relative paths. So this test, by design, will not pass on Windows.
// So just skip it.
@TestOn("!windows")
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test('uses a relative symlink for the self link', () async {
    await d.dir(appPath, [d.appPubspec(), d.libDir('foo')]).create();

    await pubGet(args: ["--packages-dir"]);

    renameInSandbox(appPath, "moved");

    await d.dir("moved", [
      d.dir("packages", [
        d.dir("myapp", [d.file('foo.dart', 'main() => "foo";')])
      ])
    ]).validate();
  });

  test('uses a relative symlink for secondary packages directory', () async {
    await d
        .dir(appPath, [d.appPubspec(), d.libDir('foo'), d.dir("bin")]).create();

    await pubGet(args: ["--packages-dir"]);

    renameInSandbox(appPath, "moved");

    await d.dir("moved", [
      d.dir("bin", [
        d.dir("packages", [
          d.dir("myapp", [d.file('foo.dart', 'main() => "foo";')])
        ])
      ])
    ]).validate();
  });
}
