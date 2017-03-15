// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("supports a user-defined lazy transformer", () {
    serveBarback();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", LAZY_TRANSFORMER)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    pubGet();
    var server = pubServe();
    // The build should complete without the transformer logging anything.
    server.stdout.expect('Build completed successfully');

    requestShouldSucceed("foo.out", "foo.out");
    server.stdout.expect(emitsLines('[Info from LazyRewrite]:\n'
        'Rewriting myapp|web/foo.txt.'));
    endPubServe();
  });
}
