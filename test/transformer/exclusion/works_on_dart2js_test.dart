// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration("works on the dart2js transformer", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "\$dart2js": {
              "\$include": ["web/a.dart", "web/b.dart"],
              "\$exclude": "web/a.dart"
            }
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("web", [
        d.file("a.dart", "void main() => print('hello');"),
        d.file("b.dart", "void main() => print('hello');"),
        d.file("c.dart", "void main() => print('hello');")
      ])
    ]).create();

    pubGet();
    var server = pubServe();
    // Dart2js should remain lazy.
    server.stdout.expect("Build completed successfully");

    requestShould404("a.dart.js");
    requestShouldSucceed("b.dart.js", isNot(isEmpty));
    server.stdout.expect(consumeThrough(emitsLines("[Info from Dart2JS]:\n"
        "Compiling myapp|web/b.dart...")));
    server.stdout.expect(consumeThrough("Build completed successfully"));

    requestShould404("c.dart.js");
    endPubServe();
  });
}
