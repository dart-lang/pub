// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  integration("exits when the connection closes", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    pubGet();
    var server = pubServe();

    // Make sure the web socket is active.
    expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "index.html")},
        {"package": "myapp", "path": "web/index.html"});

    expectWebSocketResult("exitOnClose", null, null);

    // Close the web socket.
    closeWebSocket();

    server.stdout.expect("Build completed successfully");
    server.stdout.expect("WebSocket connection closed, terminating.");
    server.shouldExit(0);
  });
}
