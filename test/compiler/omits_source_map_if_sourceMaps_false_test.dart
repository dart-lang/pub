// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("omits source maps from a debug build if sourceMaps false", () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'transformers': [
          {
            '\$dart2js': {'sourceMaps': false}
          }
        ]
      }),
      d.dir("web", [d.file("main.dart", "void main() => print('hello');")])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "--mode", "debug"],
        output: new RegExp(r'Built \d+ files to "build".'),
        exitCode: 0);

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [d.nothing('main.dart.js.map')])
      ])
    ]).validate();
  });
}
