// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

/// The code for a transformer that renames ".js" files to ".out".
const JS_REWRITE_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class RewriteTransformer extends Transformer {
  RewriteTransformer.asPlugin();

  String get allowedExtensions => '.js';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".out");
      transform.addOutput(new Asset.fromString(id, contents));
    });
  }
}
""";

main() {
  test("output can be consumed by successive phases", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["\$dart2js", "myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", JS_REWRITE_TRANSFORMER)])
      ]),
      d.dir("web", [d.file("main.dart", "void main() {}")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("main.dart.out", isUnminifiedDart2JSOutput);
    await endPubServe();
  });
}
