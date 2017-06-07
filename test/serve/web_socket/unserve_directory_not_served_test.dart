// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../utils.dart';

main() {
  test("errors if the directory is not served", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "<body>")])
    ]).create();

    await pubGet();
    await pubServe();

    // Unbind the directory.
    await expectWebSocketError("unserveDirectory", {"path": "test"}, NOT_SERVED,
        'Directory "test" is not bound to a server.');

    await endPubServe();
  });
}
