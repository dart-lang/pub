// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class DartTransformer extends Transformer {
  DartTransformer.asPlugin();

  String get allowedExtensions => '.in';

  void apply(Transform transform) {
    transform.addOutput(new Asset.fromString(
        new AssetId("myapp", "bin/script.dart"),
        "void main() => print('generated');"));
  }
}
""";

main() {
  test('runs a script generated from scratch by a transformer', () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src",
            [d.file("transformer.dart", TRANSFORMER), d.file("primary.in", "")])
      ])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ["bin/script"]);
    expect(pub.stdout, emits("generated"));
    await pub.shouldExit();
  });
}
