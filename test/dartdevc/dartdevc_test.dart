// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("can compile js files for modules under lib and web", () async {
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

    await pubGet();
    await pubServe(args: ['--web-compiler', 'dartdevc']);
    // Just confirm some basic things are present indicating that the module
    // was compiled. The goal here is not to test dartdevc itself.
    await requestShouldSucceed('web__main.js', contains('main'));
    await requestShouldSucceed('web__main.js.map', contains('web__main.js'));
    await requestShouldSucceed(
        'packages/myapp/lib__hello.js', contains('hello'));
    await requestShouldSucceed(
        'packages/myapp/lib__hello.js.map', contains('lib__hello.js'));
    await requestShouldSucceed('packages/foo/lib__foo.js', contains('message'));
    await requestShouldSucceed(
        'packages/foo/lib__foo.js.map', contains('lib__foo.js'));
    await requestShould404('invalid.js');
    await requestShould404('packages/foo/invalid.js');
    await endPubServe();
  });

  test("dartdevc resources are copied next to entrypoints", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("main.dart", 'void main() {}'),
      ]),
      d.dir("web", [
        d.file("main.dart", 'void main() {}'),
        d.dir("subdir", [
          d.file("main.dart", 'void main() {}'),
        ]),
      ]),
    ]).create();

    await pubGet();
    await pubServe(args: ['--web-compiler', 'dartdevc']);
    await requestShouldSucceed('dart_sdk.js', null);
    await requestShouldSucceed('require.js', null);
    await requestShouldSucceed('dart_stack_trace_mapper.js', null);
    await requestShouldSucceed('ddc_web_compiler.js', null);
    await requestShould404('dart_sdk.js.map');
    await requestShould404('require.js.map');
    await requestShould404('dart_stack_trace_mapper.js.map');
    await requestShould404('ddc_web_compiler.js.map');
    await requestShouldSucceed('subdir/dart_sdk.js', null);
    await requestShouldSucceed('subdir/require.js', null);
    await requestShouldSucceed('subdir/dart_stack_trace_mapper.js', null);
    await requestShouldSucceed('subdir/ddc_web_compiler.js', null);
    await requestShould404('subdir/dart_sdk.js.map');
    await requestShould404('subdir/require.js.map');
    await requestShould404('subdir/dart_stack_trace_mapper.js.map');
    await requestShould404('subdir/ddc_web_compiler.js.map');
    await endPubServe();
  });
}
