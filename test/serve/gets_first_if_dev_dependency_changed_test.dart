// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'dart:convert';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("gets first if a dev dependency has changed", () async {
    await d
        .dir("foo", [d.libPubspec("foo", "0.0.1"), d.libDir("foo")]).create();

    // Create a pubspec with "foo" and a lock file without it.
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dev_dependencies": {
          "foo": {"path": "../foo"}
        }
      }),
      d.file("pubspec.lock", JSON.encode({'packages': {}}))
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/foo/foo.dart", 'main() => "foo";');
    await endPubServe();
  });
}
