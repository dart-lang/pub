// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("'packages' URLs look in the app's lib directory", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
        d.dir("sub", [
          d.file("lib.dart", "bar() => 'bar';"),
        ])
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");
    await requestShouldSucceed(
        "packages/myapp/sub/lib.dart", "bar() => 'bar';");

    // "packages" can be in a subpath of the URL:
    await requestShouldSucceed(
        "foo/packages/myapp/lib.dart", "foo() => 'foo';");
    await requestShouldSucceed(
        "a/b/packages/myapp/sub/lib.dart", "bar() => 'bar';");
    await endPubServe();
  });
}
