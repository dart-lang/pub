// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test("binds a directory to a new port", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("test", [d.file("index.html", "<test body>")]),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe(args: ["web"]);

    // Bind the new directory.
    var response = await expectWebSocketResult("serveDirectory",
        {"path": "test"}, {"url": matches(r"http://localhost:\d+")});

    var url = Uri.parse(response["url"]);
    registerServerPort("test", url.port);

    // It should be served now.
    await requestShouldSucceed("index.html", "<test body>", root: "test");

    // And watched.
    await d.dir(appPath, [
      d.dir("test", [d.file("index.html", "after")])
    ]).create();

    await waitForBuildSuccess();
    await requestShouldSucceed("index.html", "after", root: "test");

    await endPubServe();
  });
}
