// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  // Regression test for issue 23480
  test("ignores a transformer on test files in a dependency", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("bar", "1.2.3", contents: [
        d.dir("lib", [
          // Make this invalid so that if it does get loaded, pub will
          // definitely throw an error.
          d.file("bar.dart", "{invalid Dart code)")
        ])
      ]);

      builder.serve("foo", "1.2.3", pubspec: {
        "name": "foo",
        "version": "1.0.0",
        "dev_dependencies": {"bar": "any"},
        "transformers": [
          {
            "bar": {"\$include": "test/**"}
          }
        ]
      }, contents: [
        d.dir("test", [d.file("my_test.dart", "void main() {}")])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "any"}
      }),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();

    await pubServe();
    await requestShouldSucceed("foo.txt", "foo");
    await endPubServe();
  });
}
