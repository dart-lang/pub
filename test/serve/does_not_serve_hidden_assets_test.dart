// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("doesn't serve hidden assets", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file(".outer.txt", "outer contents"),
        d.dir(".dir", [
          d.file("inner.txt", "inner contents"),
        ])
      ])
    ]).create();

    pubGet();
    pubServe();
    requestShould404(".outer.txt");
    requestShould404(".dir/inner.txt");
    endPubServe();
  });
}
