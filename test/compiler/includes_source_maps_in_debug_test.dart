// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integrationWithCompiler("includes source map URLs in a debug build",
      (compiler) {
    d.dir(appPath, [
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

    pubGet();
    schedulePub(
        args: ["build", "--mode", "debug", "--js=${compiler.name}"],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    switch (compiler) {
      case Compiler.dart2JS:
        d.dir(appPath, [
          d.dir('build', [
            d.dir('web', [
              d.matcherFile('main.dart.js',
                  contains("# sourceMappingURL=main.dart.js.map")),
              d.matcherFile(
                  'main.dart.js.map', contains('"file": "main.dart.js"'))
            ])
          ])
        ]).validate();
        break;
      case Compiler.dartDevc:
        d.dir(appPath, [
          d.dir('build', [
            d.dir('web', [
              d.dir('packages', [
                d.dir(appPath, [
                  d.matcherFile('lib__message.js',
                      contains("# sourceMappingURL=lib__message.js.map")),
                  d.matcherFile('lib__message.js.map',
                      contains('"file":"lib__message.js"')),
                ]),
              ]),
              d.matcherFile('web__main.js',
                  contains("# sourceMappingURL=web__main.js.map")),
              d.matcherFile(
                  'web__main.js.map', contains('"file":"web__main.js"')),
              // This exists to make package:test happy, but is fake (no
              // original dart file to map to).
              d.matcherFile('main.dart.js.map', anything),
            ])
          ])
        ]).validate();
        break;
    }
  });
}
