// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

// TODO(nweiz): Default to testing the native watcher and add an explicit test
// for the polling watcher when issue 14941 is fixed.

main() {
  integration(
      "stop serving a file that is removed when using the native "
      "watcher", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "body")])
    ]).create();

    pubGet();
    pubServe(args: ["--no-force-poll"]);
    requestShouldSucceed("index.html", "body");

    schedule(
        () => deleteEntry(path.join(sandboxDir, appPath, "web", "index.html")));

    waitForBuildSuccess();
    requestShould404("index.html");
    endPubServe();
  });
}
