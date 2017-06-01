// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';

main() {
  // This test is a bit shaky. Since dart2js is free to inline things, it's
  // not precise as to which source libraries will actually be referenced in
  // the source map. But this tries to use a type in the core library
  // (Duration) and validate that its source ends up in the source map.
  test(
      "Dart core libraries are available to source maps when the "
      "build directory is a subdirectory", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.dir("sub",
            [d.file("main.dart", "main() => new Duration().toString();")])
      ])
    ]).create();

    await pubGet();

    var webSub = path.join("web", "sub");
    await pubServe(args: [webSub]);

    await requestShouldSucceed(
        "main.dart.js.map", contains(r"packages/$sdk/lib/core/duration.dart"),
        root: webSub);
    await requestShouldSucceed(
        r"packages/$sdk/lib/core/duration.dart", contains("class Duration"),
        root: webSub);

    await endPubServe();
  });
}
