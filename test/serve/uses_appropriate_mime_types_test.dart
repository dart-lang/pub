// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("uses appropriate mime types", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("index.html", "<body>"),
        d.file("file.dart", "main() => print('hello');"),
        d.file("file.js", "console.log('hello');"),
        d.file("file.css", "body {color: blue}")
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("index.html", anything,
        headers: containsPair('content-type', 'text/html'));
    await requestShouldSucceed("file.dart", anything,
        headers: containsPair('content-type', 'application/dart'));
    await requestShouldSucceed("file.js", anything,
        headers: containsPair('content-type', 'application/javascript'));
    await requestShouldSucceed("file.css", anything,
        headers: containsPair('content-type', 'text/css'));
    await endPubServe();
  });
}
