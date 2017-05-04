// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration("can compile js files for modules under lib and web", () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
  String get message => 'hello';
  """)
      ]),
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        d.file(
            "hello.dart",
            """
import 'package:foo/foo.dart';

hello() => message;
""")
      ]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
import 'package:myapp/hello.dart';

void main() {
  print(hello());
}
""")
      ])
    ]).create();

    pubGet();
    pubServe(args: ['--compiler', 'dartdevc']);
    // Just confirm some basic things are present indicating that the module
    // was compiled. The goal here is not to test dartdevc itself.
    requestShouldSucceed('web__main.js', contains('main'));
    requestShouldSucceed('packages/myapp/lib__hello.js', contains('hello'));
    requestShouldSucceed('packages/foo/lib__foo.js', contains('message'));
    endPubServe();
  });
}
