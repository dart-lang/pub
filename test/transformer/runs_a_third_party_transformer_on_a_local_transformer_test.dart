// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("runs a third-party transformer on a local transformer", () {
    serveBarback();

    d.dir("foo", [
      d.libPubspec("foo", '1.0.0', deps: {"barback": "any"}),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('foo'))
      ])
    ]).create();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["foo/transformer", "myapp/transformer"],
        "dependencies": {
          "foo": {"path": "../foo"}
        }
      }),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('myapp'))
      ]),
      d.dir("web", [
        d.file("main.dart", 'const TOKEN = "main.dart";')
      ])
    ]).create();

    pubGet();
    pubServe();
    requestShouldSucceed("main.dart",
        'const TOKEN = "((main.dart, foo), (myapp, foo))";');
    endPubServe();
  });
}
