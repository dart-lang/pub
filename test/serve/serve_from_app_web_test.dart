// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("finds files in the app's web directory", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("index.html", "<body>"),
        d.file("file.dart", "main() => print('hello');"),
        d.dir("sub", [
          d.file("file.html", "<body>in subdir</body>"),
          d.file("lib.dart", "main() => 'foo';"),
        ])
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("index.html", "<body>");
    await requestShouldSucceed("file.dart", "main() => print('hello');");
    await requestShouldSucceed("sub/file.html", "<body>in subdir</body>");
    await requestShouldSucceed("sub/lib.dart", "main() => 'foo';");
    await endPubServe();
  });
}
