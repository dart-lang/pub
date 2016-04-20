// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('activating a hosted package deactivates the Git one', () {
    servePackages((builder) {
      builder.serve("foo", "2.0.0", contents: [
        d.dir("bin", [
          d.file("foo.dart", "main(args) => print('hosted');")
        ])
      ]);
    });

    d.git('foo.git', [
      d.libPubspec("foo", "1.0.0"),
      d.dir("bin", [
        d.file("foo.dart", "main() => print('git');")
      ])
    ]).create();

    schedulePub(args: ["global", "activate", "-sgit", "../foo.git"]);

    schedulePub(args: ["global", "activate", "foo"], output: """
        Package foo is currently active from Git repository "../foo.git".
        Resolving dependencies...
        + foo 2.0.0
        Downloading foo 2.0.0...
        Precompiling executables...
        Loading source assets...
        Precompiled foo:foo.
        Activated foo 2.0.0.""");

    // Should now run the hosted one.
    var pub = pubRun(global: true, args: ["foo"]);
    pub.stdout.expect("hosted");
    pub.shouldExit();
  });
}
