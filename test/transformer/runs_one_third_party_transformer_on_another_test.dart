// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("runs one third-party transformer on another", () {
    serveBarback();

    d.dir("foo", [
      d.pubspec({
        "name": "foo",
        "version": "1.0.0",
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('foo')),
      ])
    ]).create();

    d.dir("bar", [
      d.pubspec({
        "name": "bar",
        "version": "1.0.0",
        "transformers": ["foo/transformer"],
        "dependencies": {
          "foo": {"path": "../foo"},
          "barback": "any"
        }
      }),
      d.dir("lib", [
        d.file("transformer.dart", dartTransformer('bar')),
      ])
    ]).create();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["bar/transformer"],
        "dependencies": {
          'bar': {'path': '../bar'}
        }
      }),
      d.dir("web", [d.file("main.dart", 'const TOKEN = "main.dart";')])
    ]).create();

    pubGet();
    pubServe();
    requestShouldSucceed(
        "main.dart", 'const TOKEN = "(main.dart, (bar, foo))";');
    endPubServe();
  });
}
