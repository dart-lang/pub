// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration("can run dartdevc tests with pub run test", () {
    servePackages((builder) {
      builder.serveRealPackage('test');
    });

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
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"},
          "test": "any",
        },
        "transformers": ["test/pub_serve"]
      }),
      d.dir("lib", [
        d.file(
            "hello.dart",
            """
import 'package:foo/foo.dart';

hello() => message;
""")
      ]),
      d.dir("test", [
        d.file(
            "hello_test.dart",
            """
import 'package:myapp/hello.dart';
import 'package:test/test.dart';

void main() {
  test('hello is "hello"', () {
    expect(hello(), equals('hello'));
  });
}
""")
      ])
    ]).create();

    pubGet();
    pubServe(args: ['test', '--compiler', 'dartdevc']);
    schedule(() {
      var testPort = serverPorts['test'];
      expect(testPort, isNotNull);
      var process = pubRun(args: ['test:test', '--pub-serve=$testPort']);
      process.shouldExit(0);
    });
    endPubServe();
  });
}
