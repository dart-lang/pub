// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  testWithCompiler("includes source map URLs in a debug build",
      (compiler) async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [d.file("message.dart", "String get message => 'hello';")]),
      d.dir("web", [
        d.file(
            "main.dart",
            """
        import "package:$appPath/message.dart";
        void main() => print(message);
        """)
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "--mode", "debug", "--web-compiler=${compiler.name}"],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    switch (compiler) {
      case Compiler.dart2JS:
        await d.dir(appPath, [
          d.dir('build', [
            d.dir('web', [
              d.file('main.dart.js',
                  contains("# sourceMappingURL=main.dart.js.map")),
              d.file('main.dart.js.map', contains('"file": "main.dart.js"'))
            ])
          ])
        ]).validate();
        break;
      case Compiler.dartDevc:
        await d.dir(appPath, [
          d.dir('build', [
            d.dir('web', [
              d.dir('packages', [
                d.dir(appPath, [
                  d.file('lib__message.js',
                      contains("# sourceMappingURL=lib__message.js.map")),
                  d.file('lib__message.js.map',
                      contains('"file":"lib__message.js"')),
                ]),
              ]),
              d.file('web__main.js',
                  contains("# sourceMappingURL=web__main.js.map")),
              d.file('web__main.js.map', contains('"file":"web__main.js"')),
              // This exists to make package:test happy, but is fake (no
              // original dart file to map to).
              d.file('main.dart.js.map', anything),
            ])
          ])
        ]).validate();
        break;
    }
  });
}
