// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("picks up files added after serving started", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "body")])
    ]).create();

    pubGet();
    pubServe();
    waitForBuildSuccess();
    requestShouldSucceed("index.html", "body");

    d.dir(appPath, [
      d.dir("web", [d.file("other.html", "added")])
    ]).create();

    waitForBuildSuccess();
    requestShouldSucceed("other.html", "added");
    endPubServe();
  });
}
