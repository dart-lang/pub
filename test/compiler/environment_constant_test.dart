// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';
import 'utils.dart';

main() {
  group("passes environment constants to", () {
    setUp(() {
      d.dir(appPath, [
        d.appPubspec(),
        d.dir('web', [
          d.file('file.dart',
              'void main() => print(const String.fromEnvironment("name"));')
        ])
      ]).create();
    });

    integrationWithCompiler('from "pub build"', (compiler) {
      pubGet();
      schedulePub(args: [
        "build",
        "--define",
        "name=fblthp",
        "--compiler=${compiler.name}"
      ], output: new RegExp(r'Built [\d]+ file[s]? to "build".'));

      var expectedFile;
      switch (compiler) {
        case Compiler.dart2JS:
          expectedFile = d.matcherFile('file.dart.js', contains('fblthp'));
          break;
        case Compiler.dartDevc:
          expectedFile = d.matcherFile('web__file.js', contains('fblthp'));
          break;
      }

      d.dir(appPath, [
        d.dir('build', [
          d.dir('web', [expectedFile])
        ])
      ]).validate();
    });

    integrationWithCompiler('from "pub serve"', (compiler) {
      pubGet();
      pubServe(args: ["--define", "name=fblthp"], compiler: compiler);
      switch (compiler) {
        case Compiler.dart2JS:
          requestShouldSucceed("file.dart.js", contains("fblthp"));
          break;
        case Compiler.dartDevc:
          requestShouldSucceed("web__file.js", contains("fblthp"));
          break;
      }
      endPubServe();
    });

    integrationWithCompiler('which takes precedence over the pubspec',
        (compiler) {
      d.dir(appPath, [
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

      pubGet();
      pubServe(args: ["--define", "name=fblthp"], compiler: compiler);
      switch (compiler) {
        case Compiler.dart2JS:
          requestShouldSucceed("file.dart.js",
              allOf([contains("fblthp"), isNot(contains("slartibartfast"))]));
          break;
        case Compiler.dartDevc:
          requestShouldSucceed("web__file.js",
              allOf([contains("fblthp"), isNot(contains("slartibartfast"))]));
          break;
      }
      endPubServe();
    });
  });
}
