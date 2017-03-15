// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('runs the script in checked mode with "--checked"', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [d.file("script.dart", "main() { int a = true; }")])
    ]).create();

    pubGet();
    schedulePub(
        args: ["run", "--checked", "bin/script"],
        error: contains("'bool' is not a subtype of type 'int' of 'a'"),
        exitCode: 255);
  });
}
