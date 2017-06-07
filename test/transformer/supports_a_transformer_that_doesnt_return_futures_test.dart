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

class RewriteTransformer extends Transformer implements DeclaringTransformer {
  RewriteTransformer.asPlugin();

  bool isPrimary(AssetId id) => id.extension == '.txt';

  void apply(Transform transform) {
    transform.addOutput(new Asset.fromString(
        transform.primaryInput.id, "new contents"));
  }

  void declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId);
  }
}
""";

main() {
  test("supports a transformer that doesn't return futures", () async {
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
    await requestShouldSucceed("foo.txt", "new contents");
    await endPubServe();
  });
}
