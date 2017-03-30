// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("dart2js minify configuration overrides the mode", () {
    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {"minify": true}
          }
        ]
      }),
      d.dir("web", [d.file("main.dart", "void main() => print('Hello!');")])
    ]).create();

    pubGet();
    pubServe();
    requestShouldSucceed("main.dart.js", isMinifiedDart2JSOutput);
    endPubServe();
  });
}
