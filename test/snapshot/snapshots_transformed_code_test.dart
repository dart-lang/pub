// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const REPLACE_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class ReplaceTransformer extends Transformer {
  ReplaceTransformer.asPlugin();

  String get allowedExtensions => '.dart';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      transform.addOutput(new Asset.fromString(transform.primaryInput.id,
          contents.replaceAll("REPLACE ME", "hello!")));
    });
  }
}
""";

main() {
  test("snapshots the transformed version of an executable", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        "barback": "any"
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [d.file("foo.dart", REPLACE_TRANSFORMER)]),
        d.dir("bin", [
          d.file(
              "hello.dart",
              """
final message = 'REPLACE ME';

void main() => print(message);
"""),
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
    ]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("hello!"));
    await process.shouldExit();
  });
}
