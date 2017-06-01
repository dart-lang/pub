// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/compiler.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("pub build --web-compiler=dartdevc creates all required sources",
      () async {
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
"""),
        d.dir("subdir", [
          d.file(
              "subfile.dart",
              """
import '../main.dart' as other;

void main() => other.main();
"""),
        ]),
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "web", "--web-compiler=${Compiler.dartDevc.name}"],
        output: new RegExp(r'Built [\d]+ files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.file('main.dart.js', isNot(isEmpty)),
          d.file('main.dart.bootstrap.js', isNot(isEmpty)),
          d.file('dart_sdk.js', isNot(isEmpty)),
          d.file('require.js', isNot(isEmpty)),
          d.file('web__main.js', isNot(isEmpty)),
          d.file('dart_stack_trace_mapper.js', isNot(isEmpty)),
          d.file('ddc_web_compiler.js', isNot(isEmpty)),
          d.dir('packages', [
            d.dir('foo', [d.file('lib__foo.js', isNot(isEmpty))]),
            d.dir(appPath, [d.file('lib__hello.js', isNot(isEmpty))]),
          ]),
          d.file('web__subdir__subfile.js', isNot(isEmpty)),
          d.dir('subdir', [
            d.file('subfile.dart.js', isNot(isEmpty)),
            d.file(
                'subfile.dart.bootstrap.js',
                allOf(
                  contains('"web/web__main": '
                      '"../web__main"'),
                  contains(
                      '"packages/foo/lib__foo": "../packages/foo/lib__foo"'),
                )),
            d.file('dart_sdk.js', isNot(isEmpty)),
            d.file('require.js', isNot(isEmpty)),
            d.file('dart_stack_trace_mapper.js', isNot(isEmpty)),
            d.file('ddc_web_compiler.js', isNot(isEmpty)),
          ]),
        ]),
      ]),
    ]).validate();
  });
}
