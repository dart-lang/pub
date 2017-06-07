// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  test("fails to load a file that defines no transforms", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [d.file("transformer.dart", "library does_nothing;")])
    ]).create();

    await pubGet();
    var pub = await startPubServe();
    expect(pub.stderr, emits(startsWith('No transformers were defined in ')));
    expect(pub.stderr, emits(startsWith('required by myapp.')));
    expect(pub.stderrStream(),
        neverEmits(contains('This is an unexpected error')));
    await pub.shouldExit(1);
  });
}
