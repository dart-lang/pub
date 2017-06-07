// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("does not compile until its output is requested", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "version": "0.0.1",
      }),
      d.dir("web", [d.file("syntax-error.dart", "syntax error")])
    ]).create();

    await pubGet();
    var server = await pubServe();
    await expectLater(server.stdout, emits("Build completed successfully"));

    // Once we request the output, it should start compiling and fail.
    await requestShould404("syntax-error.dart.js");
    await expectLater(
        server.stdout,
        emitsLines("[Info from Dart2JS]:\n"
            "Compiling myapp|web/syntax-error.dart..."));
    await expectLater(
        server.stdout, emitsThrough("Build completed with 1 errors."));
    await endPubServe();
  });
}
