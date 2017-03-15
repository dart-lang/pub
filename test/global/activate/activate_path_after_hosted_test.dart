// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('activating a hosted package deactivates the path one', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("bin", [d.file("foo.dart", "main(args) => print('hosted');")])
      ]);
    });

    d.dir("foo", [
      d.libPubspec("foo", "2.0.0"),
      d.dir("bin", [d.file("foo.dart", "main() => print('path');")])
    ]).create();

    schedulePub(args: ["global", "activate", "foo"]);

    var path = canonicalize(p.join(sandboxDir, "foo"));
    schedulePub(
        args: ["global", "activate", "-spath", "../foo"],
        output: allOf([
          contains("Package foo is currently active at version 1.0.0."),
          contains('Activated foo 2.0.0 at path "$path".')
        ]));

    // Should now run the path one.
    var pub = pubRun(global: true, args: ["foo"]);
    pub.stdout.expect("path");
    pub.shouldExit();
  });
}
