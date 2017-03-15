// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  integration("provides output line number if given source one", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("main.dart", "main")])
    ]).create();

    pubGet();
    pubServe();

    // Paths in web/.
    expectWebSocketResult(
        "urlToAssetId",
        {"url": getServerUrl("web", "main.dart"), "line": 12345},
        {"package": "myapp", "path": "web/main.dart", "line": 12345});

    endPubServe();
  });
}
