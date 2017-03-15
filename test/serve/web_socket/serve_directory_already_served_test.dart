// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  integration("returns the old URL if the directory is already served", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    pubGet();
    pubServe();

    expectWebSocketResult(
        "serveDirectory", {"path": "web"}, {"url": getServerUrl("web")});

    endPubServe();
  });
}
