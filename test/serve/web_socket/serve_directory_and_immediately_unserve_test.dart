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
      "binds a directory to a new port and immediately unbinds that "
      "directory", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("test", [d.file("index.html", "<test body>")]),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe(args: ["web"]);

    // We call [webSocketRequest] outside of the [schedule] call below because
    // we need it to schedule the sending of the request to guarantee that the
    // serve is sent before the unserve.
    var serveRequest = webSocketRequest("serveDirectory", {"path": "test"});
    var unserveRequest = webSocketRequest("unserveDirectory", {"path": "test"});

    var results = await Future.wait([serveRequest, unserveRequest]);
    expect(results[0], contains("result"));
    expect(results[1], contains("result"));
    // These results should be equal since "serveDirectory" returns the URL
    // of the new server and "unserveDirectory" returns the URL of the
    // server that was turned off. We're asserting that the same server was
    // both started and stopped.
    expect(results[0]["result"]["url"], matches(r"http://localhost:\d+"));
    expect(results[0]["result"], equals(results[1]["result"]));

    await endPubServe();
  });
}
