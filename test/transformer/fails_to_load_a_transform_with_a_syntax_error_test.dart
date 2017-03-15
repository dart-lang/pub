// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  // A syntax error will cause the analyzer to fail to parse the transformer
  // when attempting to rewrite its imports.
  integration("fails to load a transform with a syntax error", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", "syntax error")])
      ])
    ]).create();

    pubGet();
    var pub = startPubServe();
    pub.stderr.expect(contains("unexpected token 'syntax'"));
    pub.shouldExit(1);
    pub.stderr.expect(never(contains('This is an unexpected error')));
  });
}
