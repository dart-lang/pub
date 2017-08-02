// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test("exits when the connection closes", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    var server = await pubServe();

    // Make sure the web socket is active.
    await expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "index.html")},
        {"package": "myapp", "path": "web/index.html"});

    await expectWebSocketResult("exitOnClose", null, null);

    // Close the web socket.
    await closeWebSocket();

    expect(server.stdout, emits("Build completed successfully"));
    expect(server.stdout, emits("WebSocket connection closed, terminating."));
    await server.shouldExit(0);
  });
}
