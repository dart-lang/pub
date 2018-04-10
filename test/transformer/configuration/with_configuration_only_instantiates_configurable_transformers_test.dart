// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../serve/utils.dart';
import '../../test_pub.dart';

final transformer = """
import 'dart:async';
import 'dart:convert';

import 'package:barback/barback.dart';

class ConfigTransformer extends Transformer {
  final BarbackSettings settings;

  ConfigTransformer.asPlugin(this.settings);

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".json");
      transform.addOutput(
          new Asset.fromString(id, JSON.encode(settings.configuration)));
    });
  }
}

class RewriteTransformer extends Transformer {
  RewriteTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".out");
      transform.addOutput(new Asset.fromString(id, "\$contents.out"));
    });
  }
}
""";

main() {
  test(
      "with configuration, only instantiates configurable "
      "transformers", () async {
    await serveBarback();

    var configuration = {
      "param": ["list", "of", "values"]
    };

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": [
          {"myapp/src/transformer": configuration}
        ],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", transformer)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("foo.json", json.encode(configuration));
    await requestShould404("foo.out");
    await endPubServe();
  });
}
