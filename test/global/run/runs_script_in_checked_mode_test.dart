// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';
import 'package:scheduled_test/scheduled_stream.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('runs a script in checked mode', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("bin", [
          d.file("script.dart", "main() { int a = true; }")
        ])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    var pub = pubRun(global: true, args: ["--checked", "foo:script"]);
    pub.stderr.expect(consumeThrough(contains(
        "'bool' is not a subtype of type 'int' of 'a'")));
    pub.shouldExit(255);
  });
}
