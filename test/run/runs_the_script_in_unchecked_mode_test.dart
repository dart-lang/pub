// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = """
main() {
  int a = true;
  print("no checks");
}
""";

main() {
  integration('runs the script in unchecked mode by default', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [
        d.file("script.dart", SCRIPT)
      ])
    ]).create();

    pubGet();
    schedulePub(args: ["run", "bin/script"], output: contains("no checks"));
  });
}
