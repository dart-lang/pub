// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(() {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("main.dart", "void main() => print('hello');")])
    ]).create();

    pubGet();
  });

  runTest('dart2js');
  runTest('dartdevc');
}

void runTest(String compiler) {
  group(compiler, () {
    integration("includes source map URLs in a debug build", () {
      schedulePub(
          args: ["build", "--mode", "debug", "--compiler", compiler],
          output: new RegExp(r'Built \d+ files to "build".'),
          exitCode: 0);

      d.dir(appPath, [
        d.dir('build', [
          d.dir('web', [
            d.matcherFile('main.dart.js',
                contains("# sourceMappingURL=main.dart.js.map")),
            d.matcherFile(
                'main.dart.js.map',
                anyOf(contains('"file": "main.dart.js"'),
                    contains('"file":"main.dart.js"')))
          ])
        ])
      ]).validate();
    });
  });
}
