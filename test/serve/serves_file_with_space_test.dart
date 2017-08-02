// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("serves a filename with a space", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file("foo bar.txt", "outer contents"),
        d.dir("sub dir", [
          d.file("inner.txt", "inner contents"),
        ])
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("foo%20bar.txt", "outer contents");
    await requestShouldSucceed("sub%20dir/inner.txt", "inner contents");
    await endPubServe();
  });
}
