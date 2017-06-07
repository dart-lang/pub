// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("stop serving a file that is removed", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "body")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("index.html", "body");

    deleteEntry(path.join(d.sandbox, appPath, "web", "index.html"));

    await waitForBuildSuccess();
    await requestShould404("index.html");
    await endPubServe();
  });
}
