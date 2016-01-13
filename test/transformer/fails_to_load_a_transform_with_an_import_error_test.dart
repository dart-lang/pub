// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  // An import error will cause the isolate API to fail synchronously while
  // loading the transformer.
  integration("fails to load a transform with an import error", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [d.dir("src", [
        d.file("transformer.dart", "import 'does/not/exist.dart';")
      ])])
    ]).create();

    pubGet();
    var pub = startPubServe();
    pub.stderr.expect("Unable to spawn isolate: Unhandled exception:");
    pub.stderr.expect(
        startsWith("Load Error for "));
    pub.shouldExit(1);
  });
}
