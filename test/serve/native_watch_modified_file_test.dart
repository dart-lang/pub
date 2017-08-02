// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

// TODO(nweiz): Default to testing the native watcher and add an explicit test
// for the polling watcher when issue 14941 is fixed.

main() {
  test("watches modifications to files when using the native watcher",
      () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "before")])
    ]).create();

    await pubGet();
    await pubServe(args: ["--no-force-poll"]);
    await requestShouldSucceed("index.html", "before");

    await d.dir(appPath, [
      d.dir("web", [d.file("index.html", "after")])
    ]).create();

    await waitForBuildSuccess();
    await requestShouldSucceed("index.html", "after");
    await endPubServe();
  });
}
