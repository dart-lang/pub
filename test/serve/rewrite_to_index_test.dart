// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("rewrites selected paths to index.html", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("index.html", "index contents")
      ])
    ]).create();

    pubGet();
    pubServe(args: ['--rewrite-to-index', r'^a$']);
    requestShouldSucceed("a", "index contents");
    requestShould404("dne");
    endPubServe();
  });
}
