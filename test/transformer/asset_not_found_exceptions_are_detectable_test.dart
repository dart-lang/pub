// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

final transformer = """
import 'dart:async';
import 'dart:convert';

import 'package:barback/barback.dart';

class GetInputTransformer extends Transformer {
  GetInputTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return transform.readInputAsString(new AssetId('myapp', 'nonexistent'))
        .catchError((error) {
      if (error is! AssetNotFoundException) throw error;
      transform.addOutput(new Asset.fromString(transform.primaryInput.id,
          JSON.encode({
        'package': error.id.package,
        'path': error.id.path
      })));
    });
  }
}
""";

main() {
  test("AssetNotFoundExceptions are detectable", () async {
    await serveBarback();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", transformer)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();
    var server = await pubServe();
    await requestShouldSucceed(
        "foo.txt", JSON.encode({"package": "myapp", "path": "nonexistent"}));
    await endPubServe();

    // Since the AssetNotFoundException was caught and handled, the server
    // shouldn't print any error information for it.
    expect(server.stderr, emitsDone);
  });
}
