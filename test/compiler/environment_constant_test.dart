// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';
import 'utils.dart';

main() {
  group("passes environment constants to", () {
    setUp(() {
      return d.dir(appPath, [
        d.appPubspec(),
        d.dir('web', [
          d.file('file.dart',
              'void main() => print(const String.fromEnvironment("name"));')
        ])
      ]).create();
    });

    testWithCompiler('from "pub build"', (compiler) async {
      await pubGet();
      await runPub(args: [
        "build",
        "--define",
        "name=fblthp",
        "--web-compiler=${compiler.name}"
      ], output: new RegExp(r'Built [\d]+ file[s]? to "build".'));

      var expectedFile;
      switch (compiler) {
        case Compiler.dart2JS:
          expectedFile = d.file('file.dart.js', contains('fblthp'));
          break;
        case Compiler.dartDevc:
          expectedFile = d.file('web__file.js', contains('fblthp'));
          break;
      }

      await d.dir(appPath, [
        d.dir('build', [
          d.dir('web', [expectedFile])
        ])
      ]).validate();
    });

    testWithCompiler('from "pub serve"', (compiler) async {
      await pubGet();
      await pubServe(args: ["--define", "name=fblthp"], compiler: compiler);
      switch (compiler) {
        case Compiler.dart2JS:
          await requestShouldSucceed("file.dart.js", contains("fblthp"));
          break;
        case Compiler.dartDevc:
          await requestShouldSucceed("web__file.js", contains("fblthp"));
          break;
      }
      await endPubServe();
    });

    testWithCompiler('which takes precedence over the pubspec',
        (compiler) async {
      await d.dir(appPath, [
        d.pubspec({
          "name": "myapp",
          "transformers": [
            {
              "\$dart2js": {
                "environment": {"name": "slartibartfast"}
              }
            }
          ]
        })
      ]).create();

      await pubGet();
      await pubServe(args: ["--define", "name=fblthp"], compiler: compiler);
      switch (compiler) {
        case Compiler.dart2JS:
          await requestShouldSucceed("file.dart.js",
              allOf([contains("fblthp"), isNot(contains("slartibartfast"))]));
          break;
        case Compiler.dartDevc:
          await requestShouldSucceed("web__file.js",
              allOf([contains("fblthp"), isNot(contains("slartibartfast"))]));
          break;
      }
      await endPubServe();
    });
  });
}
