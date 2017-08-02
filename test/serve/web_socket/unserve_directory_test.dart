// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test("unbinds a directory from a port", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("test", [d.file("index.html", "<test body>")]),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe();

    await requestShouldSucceed("index.html", "<body>");
    await requestShouldSucceed("index.html", "<test body>", root: "test");

    // Unbind the directory.
    await expectWebSocketResult(
        "unserveDirectory", {"path": "test"}, {"url": getServerUrl("test")});

    // "test" should not be served now.
    await requestShouldNotConnect("index.html", root: "test");

    // "web" is still fine.
    await requestShouldSucceed("index.html", "<body>");

    await endPubServe();
  });
}
