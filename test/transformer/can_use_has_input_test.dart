// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class RewriteTransformer extends Transformer {
  RewriteTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return Future.wait([
      transform.hasInput(transform.primaryInput.id),
      transform.hasInput(new AssetId('hooble', 'whatsit'))
    ]).then((results) {
      var id = transform.primaryInput.id.changeExtension(".out");
      var asset = new Asset.fromString(id,
          "primary: \${results[0]}, secondary: \${results[1]}");
      transform.addOutput(asset);
    });
  }
}
""";

main() {
  test("a transform can use hasInput", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", TRANSFORMER)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("foo.out", "primary: true, secondary: false");
    await endPubServe();
  });
}
