// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("loads a diamond transformer dependency graph", () {
    serveBarback();

    d.dir("top", [
      d.pubspec({"name": "top", "version": "1.0.0"}),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('top')),
      ])
    ]).create();

    d.dir("left", [
      d.pubspec({
        "name": "left",
        "version": "1.0.0",
        "transformers": ["top/transformer"],
        "dependencies": {
          "top": {"path": "../top"},
          "barback": "any"
        }
      }),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('left')),
      ])
    ]).create();

    d.dir("right", [
      d.pubspec({
        "name": "right",
        "version": "1.0.0",
        "transformers": ["top/transformer"],
        "dependencies": {
          "top": {"path": "../top"},
          "barback": "any"
        }
      }),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('right')),
      ])
    ]).create();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          "left/transformer",
          "right/transformer",
          "myapp/transformer"
        ],
        "dependencies": {
          'left': {'path': '../left'},
          'right': {'path': '../right'},
          'barback': 'any'
        }
      }),
      d.dir("lib", [d.file("transformer.dart", dartTransformer('myapp'))]),
      d.dir("web", [d.file("main.dart", 'const TOKEN = "main.dart";')])
    ]).create();

    pubGet();
    pubServe();
    requestShouldSucceed(
        "main.dart",
        'const TOKEN = "(((main.dart, (left, top)), (right, top)), ((myapp, '
        '(left, top)), (right, top)))";');
    endPubServe();
  });
}
