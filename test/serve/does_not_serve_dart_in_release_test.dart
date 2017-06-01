// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("does not serve .dart files in release mode", () async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
            library foo;
            foo() => 'foo';
            """)
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file("lib.dart", "lib() => print('hello');"),
      ]),
      d.dir("web", [
        d.file(
            "file.dart",
            """
            import 'package:foo/foo.dart';
            main() => print('hello');
            """),
        d.dir("sub", [
          d.file("sub.dart", "main() => 'foo';"),
        ])
      ])
    ]).create();

    await pubGet();
    await pubServe(args: ["--mode", "release"]);
    await requestShould404("file.dart");
    await requestShould404("packages/myapp/lib.dart");
    await requestShould404("packages/foo/foo.dart");
    await requestShould404("sub/sub.dart");
    await endPubServe();
  });
}
