// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("gets first if a dependency is not in the lock file", () async {
    await d
        .dir("foo", [d.libPubspec("foo", "0.0.1"), d.libDir("foo")]).create();

    // Create a lock file without "foo".
    await d.dir(appPath, [d.appPubspec()]).create();
    await pubGet();

    // Add it to the pubspec.
    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/foo/foo.dart", 'main() => "foo";');
    await endPubServe();
  });
}
