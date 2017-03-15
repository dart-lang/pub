// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class BrokenTransformer extends Transformer {
  RewriteTransformer.asPlugin() {
    throw 'This transformer is broken!';
  }

  String get allowedExtensions => '.txt';

  void apply(Transform transform) {}
}
""";

main() {
  integration("doesn't load an unnecessary transformer", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {
            "myapp/src/transformer": {r"$include": "lib/myapp.dart"}
          }
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file("myapp.dart", ""),
        d.dir("src", [d.file("transformer.dart", TRANSFORMER)])
      ]),
      d.dir("bin", [d.file("hi.dart", "void main() => print('Hello!');")])
    ]).create();

    pubGet();

    // This shouldn't load the transformer, since it doesn't transform
    // anything that the entrypoint imports. If it did load the transformer,
    // we'd know since it would throw an exception.
    var pub = pubRun(args: ["bin/hi"]);
    pub.stdout.expect("Hello!");
    pub.shouldExit();
  });
}
