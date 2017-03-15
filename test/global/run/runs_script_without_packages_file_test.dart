// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('runs a snapshotted script without a .packages file', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("bin", [d.file("script.dart", "main(args) => print('ok');")])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    // Mimic the global packages installed by pub <1.12, which didn't create a
    // .packages file for global installs.
    schedule(() {
      deleteEntry(
          p.join(sandboxDir, cachePath, 'global_packages/foo/.packages'));
    });

    var pub = pubRun(global: true, args: ["foo:script"]);
    pub.stdout.expect("ok");
    pub.shouldExit();
  });

  integration('runs an unsnapshotted script without a .packages file', () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("bin", [d.file("foo.dart", "main() => print('ok');")])
    ]).create();

    schedulePub(args: ["global", "activate", "--source", "path", "../foo"]);

    schedule(() {
      deleteEntry(
          p.join(sandboxDir, cachePath, 'global_packages/foo/.packages'));
    });

    var pub = pubRun(global: true, args: ["foo"]);
    pub.stdout.expect("ok");
    pub.shouldExit();
  });
}
