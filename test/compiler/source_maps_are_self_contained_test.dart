// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(() {
    d.dir("foo", [
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

    d.dir(appPath, [
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

    pubGet();
  });

  // This test is a bit shaky. Since dart2js is free to inline things, it's
  // not precise as to which source libraries will actually be referenced in
  // the source map. But this tries to use a type from a package and validate
  // that its source ends up in the source map with a valid URI.
  integration(
      "dart2js: source maps URIs for files in packages are self-contained", () {
    schedulePub(
        args: ["build", "--mode", "debug"],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    d.dir(appPath, [
      d.dir("build", [
        d.dir("web", [
          d.matcherFile(
              "main.dart.js.map",
              // Note: we include the quotes to ensure this is the full URL path
              // in the source map
              contains(r'"packages/foo/foo.dart"')),
          d.dir("sub", [
            d.matcherFile(
                "main2.dart.js.map", contains(r'"../packages/foo/foo.dart"'))
          ]),
          d.dir("packages", [
            d.dir(r"foo", [d.matcherFile("foo.dart", contains("foo() {"))])
          ])
        ])
      ])
    ]).validate();
  });

  // This tries to use a type from a package and validate that its source ends
  // up in the source map with a valid relative URI.
  integration("dartdevc: source maps URIs for files in packages are relative",
      () {
    schedulePub(
        args: ["build", "--mode", "debug", "--compiler", "dartdevc"],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    d.dir(appPath, [
      d.dir("build", [
        d.dir("web", [
          d.dir("packages", [
            d.dir("foo", [d.matcherFile("foo.js.map", contains(r'"foo.dart"'))])
          ]),
          d.matcherFile(
              "main.dart.module.js.map",
              allOf(contains(r'"main.dart"'),
                  isNot(contains("packages/foo/foo.dart")))),
          d.dir("sub", [
            d.matcherFile(
                "main2.dart.module.js.map",
                allOf(contains(r'"main2.dart"'),
                    isNot(contains("../packages/foo/foo.dart")))),
          ]),
          d.dir("packages", [
            d.dir(r"foo", [d.matcherFile("foo.dart", contains("foo() {"))])
          ])
        ])
      ])
    ]).validate();
  });
}
