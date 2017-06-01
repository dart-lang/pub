// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

const GROUP = """
import 'package:barback/barback.dart';

import 'transformer.dart';

class RewriteGroup implements TransformerGroup {
  RewriteGroup.asPlugin();

  Iterable<Iterable> get phases => [[new RewriteTransformer.asPlugin()]];
}
""";

main() {
  test("works on a transformer group", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "myapp/src/group": {
              "\$include": ["web/a.txt", "web/b.txt"],
              "\$exclude": "web/a.txt"
            }
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [
          d.file("transformer.dart", REWRITE_TRANSFORMER),
          d.file("group.dart", GROUP)
        ])
      ]),
      d.dir("web", [
        d.file("a.txt", "a.txt"),
        d.file("b.txt", "b.txt"),
        d.file("c.txt", "c.txt")
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShould404("a.out");
    await requestShouldSucceed("b.out", "b.txt.out");
    await requestShould404("c.out");
    await endPubServe();
  });
}
