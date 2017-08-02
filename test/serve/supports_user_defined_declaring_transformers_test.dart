// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

const DECLARING_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class DeclaringRewriteTransformer extends Transformer
    implements DeclaringTransformer {
  DeclaringRewriteTransformer.asPlugin();

  String get allowedExtensions => '.out';

  Future apply(Transform transform) {
    transform.logger.info('Rewriting \${transform.primaryInput.id}.');
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".final");
      transform.addOutput(new Asset.fromString(id, "\$contents.final"));
    });
  }

  Future declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId.changeExtension(".final"));
    return new Future.value();
  }
}
""";

main() {
  test("supports a user-defined declaring transformer", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/lazy", "myapp/src/declaring"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [
          // Include a lazy transformer before the declaring transformer,
          // because otherwise its behavior is indistinguishable from a normal
          // transformer.
          d.file("lazy.dart", LAZY_TRANSFORMER),
          d.file("declaring.dart", DECLARING_TRANSFORMER)
        ])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();
    var server = await pubServe();
    // The build should complete without either transformer logging anything.
    await expectLater(server.stdout, emits('Build completed successfully'));

    await requestShouldSucceed("foo.final", "foo.out.final");
    await expectLater(
        server.stdout,
        emitsLines('[Info from LazyRewrite]:\n'
            'Rewriting myapp|web/foo.txt.\n'
            '[Info from DeclaringRewrite]:\n'
            'Rewriting myapp|web/foo.out.'));
    await endPubServe();
  });
}
