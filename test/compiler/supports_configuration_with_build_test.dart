// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'dart:convert';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  testWithCompiler(
      "compiles dart.js and interop.js next to entrypoints when "
      "dartjs is explicitly configured", (compiler) async {
    await serve([
      d.dir('api', [
        d.dir('packages', [
          d.file(
              'browser',
              JSON.encode({
                'versions': [
                  packageVersionApiMap(packageMap('browser', '1.0.0'))
                ]
              })),
          d.dir('browser', [
            d.dir('versions', [
              d.file(
                  '1.0.0',
                  JSON.encode(packageVersionApiMap(
                      packageMap('browser', '1.0.0'),
                      full: true)))
            ])
          ])
        ])
      ]),
      d.dir('packages', [
        d.dir('browser', [
          d.dir('versions', [
            d.tar('1.0.0.tar.gz', [
              d.file('pubspec.yaml', yaml(packageMap("browser", "1.0.0"))),
              d.dir('lib', [
                d.file('dart.js', 'contents of dart.js'),
                d.file('interop.js', 'contents of interop.js')
              ])
            ])
          ])
        ])
      ])
    ]);

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"browser": "1.0.0"},
        "transformers": [
          {
            "\$dart2js": {"minify": true}
          }
        ]
      }),
      d.dir('web', [
        d.file('file.dart', 'void main() => print("hello");'),
      ])
    ]).create();

    await pubGet();

    await runPub(
        args: ["build", "--web-compiler", compiler.name],
        output: new RegExp(r'Built \d+ files? to "build".'),
        exitCode: 0);

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.file('file.dart.js', isMinifiedDart2JSOutput),
          d.dir('packages', [
            d.dir('browser', [
              d.file('dart.js', 'contents of dart.js'),
              d.file('interop.js', 'contents of interop.js')
            ])
          ]),
        ])
      ])
    ]).validate();
  });
}
