// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  testWithCompiler("compiles a Dart file that imports a generated file to JS",
      (compiler) async {
    await serveBarback();

    await d.dir(appPath, [
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
import "other.dart";
void main() => print(TOKEN);
"""),
        d.file(
            "other.dart",
            """
const TOKEN = "before";
""")
      ])
    ]).create();

    await pubGet();
    await pubServe(compiler: compiler);
    switch (compiler) {
      case Compiler.dart2JS:
        await requestShouldSucceed("main.dart.js", contains("(before, munge)"));
        break;
      case Compiler.dartDevc:
        await requestShouldSucceed("web__main.js", contains("(before, munge)"));
        break;
    }
    await endPubServe();
  });
}
