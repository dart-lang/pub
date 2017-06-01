// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("runs a third-party transform on the application package", () async {
    await serveBarback();

    await d.dir("foo", [
      d.libPubspec("foo", '1.0.0', deps: {"barback": "any"}),
      d.dir("lib", [d.file("foo.dart", REWRITE_TRANSFORMER)])
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["foo"],
        "dependencies": {
          "foo": {"path": "../foo"}
        }
      }),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("foo.out", "foo.out");
    await endPubServe();
  });
}
