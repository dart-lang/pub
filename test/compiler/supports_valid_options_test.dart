// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("supports most dart2js command-line options", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {
              "commandLineOptions": ["--enable-diagnostic-colors"],
              "checked": true,
              "csp": true,
              "minify": true,
              "verbose": true,
              "environment": {"name": "value"},
              // TODO(nweiz): Re-add these when sdk#24653 is fixed.
              // "suppressWarnings": true,
              // "suppressHints": true,
              "suppressPackageWarnings": false,
              "terse": true,
              "sourceMaps": false
            }
          }
        ]
      }),
      d.dir("web", [d.file("main.dart", "void main() => print('Hello!');")])
    ]).create();

    await pubGet();

    // None of these options should be rejected, either by pub or by dart2js.
    await pubServe();
    await requestShouldSucceed("main.dart.js", isNot(isEmpty));
    await endPubServe();
  });
}
