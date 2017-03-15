// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = """
import 'dart:io';

main() {
  stdout.writeln("stdout output");
  stderr.writeln("stderr output");
  exitCode = 123;
}
""";

main() {
  integration('allows a ".dart" extension on the argument', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [d.file("script.dart", SCRIPT)])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["script.dart"]);
    pub.stdout.expect("stdout output");
    pub.stderr.expect("stderr output");
    pub.shouldExit(123);
  });
}
