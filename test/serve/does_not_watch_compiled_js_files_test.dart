// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("does not watch changes to compiled JS files in the package", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("index.html", "body")])
    ]).create();

    await pubGet();
    await pubServe();
    await waitForBuildSuccess();
    await requestShouldSucceed("index.html", "body");
    await d.dir(appPath, [
      d.dir("web", [
        d.file('file.dart', 'void main() => print("hello");'),
        d.file("other.dart.js", "should be ignored"),
        d.file("other.dart.js.map", "should be ignored"),
        d.file("other.dart.precompiled.js", "should be ignored")
      ])
    ]).create();

    await waitForBuildSuccess();
    await requestShouldSucceed("file.dart", 'void main() => print("hello");');
    await requestShould404("other.dart.js");
    await requestShould404("other.dart.js.map");
    await requestShould404("other.dart.precompiled.js");
    await endPubServe();
  });
}
