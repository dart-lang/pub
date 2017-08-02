// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test(
      "binds a directory to a new port and immediately binds that "
      "directory again", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("test", [d.file("index.html", "<test body>")]),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe(args: ["web"]);

    var results = await Future.wait([
      webSocketRequest("serveDirectory", {"path": "test"}),
      webSocketRequest("serveDirectory", {"path": "test"})
    ]);
    expect(results[0], contains("result"));
    expect(results[1], contains("result"));
    expect(results[0]["result"], equals(results[1]["result"]));

    await endPubServe();
  });
}
