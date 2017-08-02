// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

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
  test("reports failures in transformers which don't output dart", () async {
    // Test for https://github.com/dart-lang/pub/issues/1336
    await serveBarback();

    await d.dir(appPath, [
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

    await pubGet();
    await runPub(args: ["build"], exitCode: 65);
  });
}
