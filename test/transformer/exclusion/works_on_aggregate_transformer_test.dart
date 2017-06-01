// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

const AGGREGATE_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

class ManyToOneTransformer extends AggregateTransformer {
  ManyToOneTransformer.asPlugin();

  String classifyPrimary(AssetId id) {
    if (id.extension != '.txt') return null;
    return p.url.dirname(id.path);
  }

  Future apply(AggregateTransform transform) {
    return transform.primaryInputs.toList().then((assets) {
      assets.sort((asset1, asset2) => asset1.id.path.compareTo(asset2.id.path));
      return Future.wait(assets.map((asset) => asset.readAsString()));
    }).then((contents) {
      var id = new AssetId(transform.package,
          p.url.join(transform.key, 'out.txt'));
      transform.addOutput(new Asset.fromString(id, contents.join('\\n')));
    });
  }
}
""";

main() {
  test("works on an aggregate transformer", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "myapp": {
              "\$include": ["web/a.txt", "web/b.txt", "web/c.txt"],
              "\$exclude": "web/a.txt"
            }
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file("transformer.dart", AGGREGATE_TRANSFORMER),
      ]),
      d.dir("web", [
        d.file("a.txt", "a"),
        d.file("b.txt", "b"),
        d.file("c.txt", "c"),
        d.file("d.txt", "d")
      ])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("out.txt", "b\nc");
    await endPubServe();
  });
}
