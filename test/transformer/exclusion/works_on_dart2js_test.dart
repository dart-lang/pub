// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  test("works on the dart2js transformer", () async {
    await serveBarback();

    await d.dir(appPath, [
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

    await pubGet();
    var server = await pubServe();
    // Dart2js should remain lazy.
    expect(server.stdout, emits("Build completed successfully"));

    await requestShould404("a.dart.js");
    await requestShouldSucceed("b.dart.js", isNot(isEmpty));
    expect(
        server.stdout,
        emitsThrough(emitsLines("[Info from Dart2JS]:\n"
            "Compiling myapp|web/b.dart...")));
    expect(server.stdout, emitsThrough("Build completed successfully"));

    await requestShould404("c.dart.js");
    await endPubServe();
  });
}
