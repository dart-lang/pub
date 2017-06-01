// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("fails to load a non-existent transform", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/transform"]
      })
    ]).create();

    await pubGet();
    var pub = await startPubServe();
    expect(pub.stderr,
        emits('Transformer library "package:myapp/transform.dart" not found.'));
    await pub.shouldExit(1);
  });
}
