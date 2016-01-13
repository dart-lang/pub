// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

// TODO(nweiz): Default to testing the native watcher and add an explicit test
// for the polling watcher when issue 14941 is fixed.

main() {
  integration("watches modifications to files when using the native watcher",
      () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("index.html", "before")
      ])
    ]).create();

    pubGet();
    pubServe(args: ["--no-force-poll"]);
    requestShouldSucceed("index.html", "before");

    d.dir(appPath, [
      d.dir("web", [
        d.file("index.html", "after")
      ])
    ]).create();

    waitForBuildSuccess();
    requestShouldSucceed("index.html", "after");
    endPubServe();
  });
}
