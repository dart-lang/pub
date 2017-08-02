// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test(
      "binds a directory to a new port and immediately requests an "
      "asset URL from that server", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("test", [d.file("index.html", "<test body>")]),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe(args: ["web"]);

    // Bind the new directory.
    await expectLater(
        webSocketRequest("serveDirectory", {"path": "test"}), completes);

    await expectWebSocketResult("pathToUrls", {
      "path": "test/index.html"
    }, {
      "urls": [endsWith("/index.html")]
    });

    await endPubServe();
  });
}
