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
  final BarbackSettings _settings;

  DartTransformer.asPlugin(this._settings);

  String get allowedExtensions => '.in';

  void apply(Transform transform) {
    transform.addOutput(new Asset.fromString(
        new AssetId(transform.primaryInput.id.package, "bin/script.dart"),
        "void main() => print('\${_settings.mode.name}');"));
  }
}
""";

main() {
  test('runs a local script with customizable modes', () async {
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

    // By default it should run in debug mode.
    var pub = await pubRun(args: ["bin/script"]);
    expect(pub.stdout, emits("debug"));
    await pub.shouldExit();

    // A custom mode should be specifiable.
    pub = await pubRun(args: ["--mode", "custom-mode", "bin/script"]);
    expect(pub.stdout, emits("custom-mode"));
    await pub.shouldExit();
  });

  test('runs a dependency script with customizable modes', () async {
    await serveBarback();

    await d.dir("foo", [
      d.pubspec({
        "name": "foo",
        "version": "1.2.3",
        "transformers": ["foo/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.dir("src",
            [d.file("transformer.dart", TRANSFORMER), d.file("primary.in", "")])
      ])
    ]).create();

    await d.appDir({
      "foo": {"path": "../foo"}
    }).create();

    await pubGet();

    // By default it should run in release mode.
    var pub = await pubRun(args: ["foo:script"]);
    expect(pub.stdout, emits("release"));
    await pub.shouldExit();

    // A custom mode should be specifiable.
    pub = await pubRun(args: ["--mode", "custom-mode", "foo:script"]);
    expect(pub.stdout, emits("custom-mode"));
    await pub.shouldExit();
  });
}
