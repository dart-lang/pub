// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = """
main() {
  print("should not get here!");
}
""";

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class FailingTransformer extends Transformer {
  FailingTransformer.asPlugin();

  String get allowedExtensions => '.dart';

  void apply(Transform transform) {
    // Don't run on the transformer itself.
    if (transform.primaryInput.id.path.startsWith("lib")) return;
    transform.logger.error('\${transform.primaryInput.id}.');
  }
}
""";

main() {
  test('does not run if a transformer has an error', () async {
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
      d.dir("bin", [d.file("script.dart", SCRIPT)])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ["bin/script"]);

    expect(pub.stderr, emits("[Error from Failing]:"));
    expect(pub.stderr, emits("myapp|bin/script.dart."));

    // Note: no output from the script.
    await pub.shouldExit();
  });
}
