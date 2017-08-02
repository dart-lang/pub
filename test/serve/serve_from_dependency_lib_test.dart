// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("'packages' URLs look in the dependency's lib directory", () async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
        d.dir("sub", [
          d.file("lib.dart", "bar() => 'bar';"),
        ])
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/foo/lib.dart", "foo() => 'foo';");
    await requestShouldSucceed("packages/foo/sub/lib.dart", "bar() => 'bar';");

    // "packages" can be in a subpath of the URL:
    await requestShouldSucceed("foo/packages/foo/lib.dart", "foo() => 'foo';");
    await requestShouldSucceed(
        "a/b/packages/foo/sub/lib.dart", "bar() => 'bar';");
    await endPubServe();
  });
}
