// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration(
      "compiles a Dart file that imports a generated file in another "
      "package to JS", () {
    serveBarback();

    d.dir("foo", [
      d.pubspec({
        "name": "foo",
        "version": "0.0.1",
        "transformers": ["foo/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
const TOKEN = "before";
foo() => TOKEN;
"""),
        d.file("transformer.dart", dartTransformer("munge"))
      ])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("web", [
        d.file(
            "main.dart",
            """
import "package:foo/foo.dart";
main() => print(foo());
""")
      ])
    ]).create();

    pubGet();
    pubServe();
    requestShouldSucceed("main.dart.js", contains("(before, munge)"));
    endPubServe();
  });
}
