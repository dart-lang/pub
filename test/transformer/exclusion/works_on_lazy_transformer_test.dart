// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  test("works on a lazy transformer", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "myapp": {
              "\$include": ["web/a.txt", "web/b.txt"],
              "\$exclude": "web/a.txt"
            }
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [d.file("transformer.dart", LAZY_TRANSFORMER)]),
      d.dir("web",
          [d.file("a.txt", "a"), d.file("b.txt", "b"), d.file("c.txt", "c")])
    ]).create();

    await pubGet();
    var server = await pubServe();
    // The transformer should remain lazy.
    expect(server.stdout, emits("Build completed successfully"));

    await requestShould404("a.out");
    await requestShouldSucceed("b.out", isNot(isEmpty));
    expect(
        server.stdout,
        emitsThrough(emitsLines("[Info from LazyRewrite]:\n"
            "Rewriting myapp|web/b.txt.")));
    expect(server.stdout, emitsThrough("Build completed successfully"));

    await requestShould404("c.out");
    await endPubServe();
  });
}
