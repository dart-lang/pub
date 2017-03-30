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

    testFromPubBuild("dart2js");
    testFromPubBuild("dartdevc",
        skip: 'TODO(jakemac53): forward environment config to dartdevc');

    testFromPubServe("dart2js");
    testFromPubServe("dartdevc",
        skip: 'TODO(jakemac53): forward environment config to dartdevc');

    testTakesPrecedence("dart2js");
    testTakesPrecedence("dartdevc",
        skip: 'TODO(jakemac53): allow environment configuration for dartdevc '
            'via transformer config.');
  });
}

void testFromPubBuild(String compiler, {skip}) {
  integration('$compiler from "pub build"', () {
    pubGet();
    schedulePub(
        args: ["build", "--define", "name=fblthp", "--compiler=$compiler"],
        output: new RegExp(r'Built 1 file to "build".'));

    d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.matcherFile('file.dart.js', contains('fblthp')),
        ])
      ])
    ]).validate();
  }, skip: skip);
}

void testFromPubServe(String compiler, {skip}) {
  integration('$compiler from "pub serve"', () {
    pubGet();
    pubServe(args: ["--define", "name=fblthp", "--compiler=$compiler"]);
    requestShouldSucceed("file.dart.js", contains("fblthp"));
    endPubServe();
  }, skip: skip);
}

void testTakesPrecedence(String compiler, {skip}) {
  integration('$compiler which takes precedence over the pubspec', () {
    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$$compiler": {
              "environment": {"name": "slartibartfast"}
            }
          }
        ]
      })
    ]).create();

    pubGet();
    pubServe(args: ["--define", "name=fblthp", "--compiler=$compiler"]);
    requestShouldSucceed("file.dart.js",
        allOf([contains("fblthp"), isNot(contains("slartibartfast"))]));
    endPubServe();
  }, skip: skip);
}
