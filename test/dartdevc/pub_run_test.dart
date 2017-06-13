// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("can run dartdevc tests with pub run test", () async {
    await servePackages((builder) {
      builder.serveRealPackage('test');
    });

    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file(
            "foo.dart",
            """
  String get message => 'hello';
  """)
      ]),
    ]).create();

    await d.dir(appPath, [
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

    await pubGet();
    await pubServe(args: ['test', '--web-compiler', 'dartdevc']);
    var testPort = serverPorts['test'];
    expect(testPort, isNotNull);
    var testProcess =
        await pubRun(args: ['test:test', '--pub-serve=$testPort']);
    expect(await testProcess.exitCode, SUCCESS);
    expect(
        testProcess.stdout,
        emitsThrough(emitsInOrder([
          contains('test/hello_test.dart: hello is "hello"'),
          allOf(contains('+1'), contains('All tests passed!'))
        ])));
    endPubServe();
  });
}
