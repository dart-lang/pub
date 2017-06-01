// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  testWithCompiler("handles imports in the Dart code", (compiler) async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
foo() => 'footext';
""")
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file(
            "lib.dart",
            """
lib() => 'libtext';
""")
      ]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
import 'package:foo/foo.dart';
import 'package:myapp/lib.dart';
void main() {
  print(foo());
  print(lib());
}
""")
      ])
    ]).create();

    await pubGet();
    await pubServe(compiler: compiler);
    switch (compiler) {
      case Compiler.dart2JS:
        await requestShouldSucceed("main.dart.js", contains("footext"));
        await requestShouldSucceed("main.dart.js", contains("libtext"));
        break;
      case Compiler.dartDevc:
        await requestShouldSucceed(
            "main.dart.js", contains("main.dart.bootstrap"));
        await requestShouldSucceed(
            "main.dart.bootstrap.js", contains("web__main"));
        await requestShouldSucceed(
            "web__main.js", allOf(contains("foo"), contains("lib")));
        await requestShouldSucceed(
            "packages/foo/lib__foo.js", contains("footext"));
        await requestShouldSucceed(
            "packages/myapp/lib__lib.js", contains("libtext"));
        break;
    }
    await endPubServe();
  });
}
