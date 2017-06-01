// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

const REJECT_CONFIG_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class RejectConfigTransformer extends Transformer {
  RejectConfigTransformer.asPlugin(BarbackSettings settings) {
    throw "I hate these settings!";
  }

  Future<bool> isPrimary(_) => new Future.value(true);
  Future apply(Transform transform) {}
}
""";

main() {
  test(
      "multiple transformers in the same phase reject their "
      "configurations", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          [
            {
              "myapp/src/transformer": {'foo': 'bar'}
            },
            {
              "myapp/src/transformer": {'baz': 'bang'}
            },
            {
              "myapp/src/transformer": {'qux': 'fblthp'}
            }
          ]
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", REJECT_CONFIG_TRANSFORMER)])
      ])
    ]).create();

    await pubGet();
    // We should see three instances of the error message, once for each
    // use of the transformer.
    var pub = await startPubServe();
    for (var i = 0; i < 3; i++) {
      expect(
          pub.stderr,
          emitsThrough(endsWith('Error loading transformer: '
              'I hate these settings!')));
    }
    await pub.shouldExit(1);
  });
}
