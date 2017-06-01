// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  // This test is a bit shaky. Since dart2js is free to inline things, it's
  // not precise as to which source libraries will actually be referenced in
  // the source map. But this tries to use a type from a package and validate
  // that its source ends up in the source map with a valid URI.
  testWithCompiler("Source maps URIs for files in packages are self-contained",
      (compiler) async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
            library foo;
            foo() {
              // As of today dart2js will not inline this code.
              if ('\${new DateTime.now()}' == 'abc') return 1;
              return 2;
            }
            """)
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("web", [
        d.file(
            "main.dart",
            """
            import 'package:foo/foo.dart';
            main() => foo();
            """),
        d.dir("sub", [
          d.file(
              "main2.dart",
              """
            import 'package:foo/foo.dart';
            main() => foo();
            """),
        ])
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "--mode", "debug", "--web-compiler", compiler.name],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    var expectedWebDir;
    switch (compiler) {
      case Compiler.dart2JS:
        expectedWebDir = d.dir("web", [
          d.file(
              "main.dart.js.map",
              // Note: we include the quotes to ensure this is the full URL path
              // in the source map
              contains(r'"packages/foo/foo.dart"')),
          d.dir("sub", [
            d.file(
                "main2.dart.js.map", contains(r'"../packages/foo/foo.dart"')),
          ]),
          d.dir("packages", [
            d.dir(r"foo", [d.file("foo.dart", contains("foo() {"))]),
          ]),
        ]);
        break;
      case Compiler.dartDevc:
        expectedWebDir = d.dir("web", [
          d.dir("packages", [
            d.dir("foo", [
              d.file("foo.dart", contains("foo() {")),
              d.file('lib__foo.js', contains("foo.dart")),
            ]),
          ]),
          d.file("web__main.js.map", contains(r'"main.dart"')),
          d.file("web__sub__main2.js.map", contains(r'"sub/main2.dart"')),
        ]);

        break;
    }

    await d.dir(appPath, [
      d.dir("build", [expectedWebDir])
    ]).validate();
  });
}
