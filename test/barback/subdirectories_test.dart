// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';

main() {
  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.dir("one", [
          d.dir("inner", [d.file("file.txt", "one")])
        ]),
        d.dir("two", [
          d.dir("inner", [d.file("file.txt", "two")])
        ]),
        d.dir("nope", [
          d.dir("inner", [d.file("file.txt", "nope")])
        ])
      ])
    ]).create();

    await pubGet();
  });

  var webOne = p.join("web", "one");
  var webTwoInner = p.join("web", "two", "inner");

  test("builds subdirectories", () async {
    await runPub(
        args: ["build", webOne, webTwoInner],
        output: new RegExp(r'Built 2 files to "build".'));

    await d.dir(appPath, [
      d.dir("build", [
        d.dir("web", [
          d.dir("one", [
            d.dir("inner", [d.file("file.txt", "one")])
          ]),
          d.dir("two", [
            d.dir("inner", [d.file("file.txt", "two")])
          ]),
          d.nothing("nope")
        ])
      ])
    ]).validate();
  });

  test("serves subdirectories", () async {
    await pubServe(args: [webOne, webTwoInner]);

    await requestShouldSucceed("inner/file.txt", "one", root: webOne);
    await requestShouldSucceed("file.txt", "two", root: webTwoInner);
    await expectNotServed("web");
    await expectNotServed(p.join("web", "three"));

    await endPubServe();
  });
}
