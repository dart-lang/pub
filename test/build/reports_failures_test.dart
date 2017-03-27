// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _failingTransformer = """
import 'dart:async';

import 'package:barback/barback.dart';

class FailingTransformer extends Transformer {
  FailingTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    throw 'FAIL!';
  }
}
""";

main() {
  integration("reports failures in transformers which don't output dart", () {
    // Test for https://github.com/dart-lang/pub/issues/1336
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", _failingTransformer)])
      ]),
      d.dir("web",
          [d.file("foo.txt", "foo"), d.file("main.dart", "void main() {}")])
    ]).create();

    pubGet();
    schedulePub(args: ["build"], exitCode: 65);
  });
}
