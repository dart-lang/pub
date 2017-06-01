// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test('runs the script in checked mode with "--checked"', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("bin", [d.file("script.dart", "main() { int a = true; }")])
    ]).create();

    await pubGet();
    await runPub(
        args: ["run", "--checked", "bin/script"],
        error: contains("'bool' is not a subtype of type 'int' of 'a'"),
        exitCode: 255);
  });
}
