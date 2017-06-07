// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("doesn't support an invalid dart2js option", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {"invalidOption": true}
          }
        ]
      })
    ]).create();

    await pubGet();

    // TODO(nweiz): This should provide more context about how the option got
    // passed to dart2js. See issue 16008.
    var pub = await startPubServe();
    await expect(
        pub.stderr, emits('Unrecognized dart2js option "invalidOption".'));
    await pub.shouldExit(exit_codes.DATA);
  });
}
