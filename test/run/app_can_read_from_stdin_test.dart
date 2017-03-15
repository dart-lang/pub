// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('the spawned application can read line-by-line from stdin', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [
        d.file(
            "script.dart",
            """
          import 'dart:io';

          main() {
            print("started");
            var line1 = stdin.readLineSync();
            print("between");
            var line2 = stdin.readLineSync();
            print(line1);
            print(line2);
          }
        """)
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    pub.stdout.expect("started");
    pub.writeLine("first");
    pub.stdout.expect("between");
    pub.writeLine("second");
    pub.stdout.expect("first");
    pub.stdout.expect("second");
    pub.shouldExit(0);
  });

  integration('the spawned application can read streamed from stdin', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [
        d.file(
            "script.dart",
            """
          import 'dart:io';

          main() {
            print("started");
            stdin.listen(stdout.add);
          }
        """)
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    pub.stdout.expect("started");
    pub.writeLine("first");
    pub.stdout.expect("first");
    pub.writeLine("second");
    pub.stdout.expect("second");
    pub.writeLine("third");
    pub.stdout.expect("third");
    pub.closeStdin();
    pub.shouldExit(0);
  });
}
