// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  setUp(() {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "version": "0.0.1",
        "transformers": ["myapp/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [d.file("transformer.dart", dartTransformer("munge"))]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
const TOKEN = "before";
void main() => print(TOKEN);
""")
      ])
    ]).create();
    pubGet();
  });

  tearDown(() {
    endPubServe();
  });

  integration("dart2js compiles a generated Dart file to JS", () {
    pubServe();
    requestShouldSucceed("main.dart.js", contains("(before, munge)"));
  });

  integration("dartdevc compiles a generated Dart file to JS", () {
    pubServe(args: ['--compiler=dartdevc']);
    // AMD Bootstrap file.
    requestShouldSucceed(
        "main.dart.js",
        '''
require(["main.dart.module", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.web__main.main();
});
''');
    // Actual entry point module.
    requestShouldSucceed("main.dart.module.js", contains("(before, munge)"));
  });
}
