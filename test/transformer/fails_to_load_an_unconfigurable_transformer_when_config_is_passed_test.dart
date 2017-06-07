// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test(
      "fails to load an unconfigurable transformer when config is "
      "passed", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "myapp/src/transformer": {'foo': 'bar'}
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", REWRITE_TRANSFORMER)])
      ])
    ]).create();

    await pubGet();
    var pub = await startPubServe();
    expect(
        pub.stderr,
        emits(startsWith('No transformers that accept configuration '
            'were defined in ')));
    await pub.shouldExit(1);
  });
}
