// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("supports a user-defined lazy transformer", () async {
    await serveBarback();

    await d.dir(appPath, [
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

    await pubGet();
    var server = await pubServe();
    // The build should complete without the transformer logging anything.
    await expectLater(server.stdout, emits('Build completed successfully'));

    await requestShouldSucceed("foo.out", "foo.out");
    await expectLater(
        server.stdout,
        emitsLines('[Info from LazyRewrite]:\n'
            'Rewriting myapp|web/foo.txt.'));
    await endPubServe();
  });
}
