// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("serves index.html for directories", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("index.html", "<body>super"),
        d.dir("sub", [d.file("index.html", "<body>sub")])
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("", "<body>super");
    await requestShouldSucceed("sub/", "<body>sub");
    await requestShouldRedirect("sub", "/sub/");
    await endPubServe();
  });
}
