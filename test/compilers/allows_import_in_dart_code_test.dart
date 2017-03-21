// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  setUp(() {
    d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
foo() => 'footext';
""")
      ])
    ]).create();

    d.dir(appPath, [
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

    pubGet();
  });

  tearDown(() {
    endPubServe();
  });

  integration("dart2js handles imports in the Dart code", () {
    pubServe();
    requestShouldSucceed("main.dart.js", contains("footext"));
    requestShouldSucceed("main.dart.js", contains("libtext"));
  });

  integration("dartdevc handles imports in the Dart code", () {
    pubServe(args: ['--compiler=dartdevc']);
    requestShouldSucceed("main.dart.js", contains("foo()"));
    requestShouldSucceed("main.dart.js", contains("lib()"));
    requestShouldSucceed("packages/foo/foo.js", contains("footext"));
    requestShouldSucceed("packages/myapp/myapp.js", contains("libtext"));
  });
}
