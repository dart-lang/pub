// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/barback/compiler.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("pub build --compiler=dartdevc creates all required sources", () {
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

    pubGet();
    schedulePub(
        args: ["build", "web", "--compiler=${Compiler.dartDevc.name}"],
        output: new RegExp(r'Built [\d]+ files to "build".'));

    d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.matcherFile('main.dart.js', isNot(isEmpty)),
          d.matcherFile('main.dart.bootstrap.js', isNot(isEmpty)),
          d.matcherFile('dart_sdk.js', isNot(isEmpty)),
          d.matcherFile('require.js', isNot(isEmpty)),
          d.matcherFile('web__main.js', isNot(isEmpty)),
          d.dir('packages', [
            d.dir('foo', [d.matcherFile('lib__foo.js', isNot(isEmpty))]),
            d.dir(appPath, [d.matcherFile('lib__hello.js', isNot(isEmpty))]),
          ]),
          d.matcherFile('web__subdir__subfile.js', isNot(isEmpty)),
          d.dir('subdir', [
            d.matcherFile('subfile.dart.js', isNot(isEmpty)),
            d.matcherFile(
                'subfile.dart.bootstrap.js',
                allOf(
                  contains('"web/web__main": '
                      '"../web__main"'),
                  contains(
                      '"packages/foo/lib__foo": "../packages/foo/lib__foo"'),
                )),
            d.matcherFile('dart_sdk.js', isNot(isEmpty)),
            d.matcherFile('require.js', isNot(isEmpty)),
          ]),
        ]),
      ]),
    ]).validate();
  });
}
