// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test('replaces a broken "packages" symlink', () async {
    await d
        .dir(appPath, [d.appPubspec(), d.libDir('foo'), d.dir("bin")]).create();

    // Create a broken "packages" symlink in "bin".
    symlinkInSandbox("nonexistent", path.join(appPath, "packages"));

    await pubGet(args: ["--packages-dir"]);

    await d.dir(appPath, [
      d.dir("bin", [
        d.dir("packages", [
          d.dir("myapp", [d.file('foo.dart', 'main() => "foo";')])
        ])
      ])
    ]).validate();
  });

  test('replaces a broken secondary "packages" symlink', () async {
    await d
        .dir(appPath, [d.appPubspec(), d.libDir('foo'), d.dir("bin")]).create();

    // Create a broken "packages" symlink in "bin".
    symlinkInSandbox("nonexistent", path.join(appPath, "bin", "packages"));

    await pubGet(args: ["--packages-dir"]);

    await d.dir(appPath, [
      d.dir("bin", [
        d.dir("packages", [
          d.dir("myapp", [d.file('foo.dart', 'main() => "foo";')])
        ])
      ])
    ]).validate();
  });
}
