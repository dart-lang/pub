// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  // This is a regression test for http://dartbug.com/21402.
  test(
      "picks up files replaced after serving started when using the "
      "native watcher", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", REWRITE_TRANSFORMER)])
      ]),
      d.dir("web", [
        d.file("file.txt", "before"),
      ]),
      d.file("other", "after")
    ]).create();

    await pubGet();
    await pubServe(args: ["--no-force-poll"]);
    await waitForBuildSuccess();
    await requestShouldSucceed("file.out", "before.out");

    // Replace file.txt by renaming other on top of it.
    new File(p.join(d.sandbox, appPath, "other"))
        .renameSync(p.join(d.sandbox, appPath, "web", "file.txt"));

    // Read the transformed file to ensure the change is actually noticed by
    // pub and not that we just get the new file contents piped through
    // without pub realizing they've changed.
    await waitForBuildSuccess();
    await requestShouldSucceed("file.out", "after.out");

    await endPubServe();
  });
}
