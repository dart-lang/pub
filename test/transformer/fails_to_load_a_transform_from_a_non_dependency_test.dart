// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("fails to load a transform from a non-dependency", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["foo"]
      })
    ]).create();

    await pubGet();
    var pub = await startPubServe();
    expect(pub.stderr, emits(contains('"foo" is not a dependency.')));
    await pub.shouldExit(exit_codes.DATA);
  });
}
