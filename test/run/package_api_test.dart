// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class MyTransformer extends Transformer {
  MyTransformer.asPlugin();

  String get allowedExtensions => '.in';

  Future apply(Transform transform) async {
    transform.addOutput(new Asset.fromString(
        transform.primaryInput.id.changeExtension('.txt'),
        await transform.primaryInput.readAsString()));
  }
}
""";

main() {
  integration('an untransformed application sees a file: package config', () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0")
    ]).create();

    d.dir(appPath, [
      d.appPubspec({"foo": {"path": "../foo"}}),
      d.dir("bin", [
        d.file("script.dart", """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:myapp/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
}
""")
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    pub.stdout.expect("null");
    pub.stdout.expect(
        p.toUri(p.join(sandboxDir, "myapp/.packages")).toString());
    pub.stdout.expect(
        p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")).toString());
    pub.stdout.expect(
        p.toUri(p.join(sandboxDir, "foo/lib/resource.txt")).toString());
    pub.shouldExit(0);
  });

  integration('a transformed application sees an http: package root', () {
    serveBarback();

    d.dir("foo", [
      d.libPubspec("foo", "1.0.0")
    ]).create();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "transformers": ["myapp/src/transformer"],
        "dependencies": {"barback": "any"}
      }),
      d.dir("lib", [
        d.file("resource.in", "hello!"),
        d.dir("src", [
          d.file("transformer.dart", TRANSFORMER)
        ])
      ]),
      d.dir("bin", [
        d.file("script.dart", """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:myapp/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
}
""")
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    pub.stdout.expect(
        allOf(startsWith("http://localhost:"), endsWith("/packages/")));
    pub.stdout.expect("null");
    pub.stdout.expect(allOf(
        startsWith("http://localhost:"),
        endsWith("/packages/myapp/resource.txt")));
    pub.stdout.expect(allOf(
        startsWith("http://localhost:"),
        endsWith("/packages/foo/resource.txt")));
    pub.shouldExit(0);
  });

  integration('a snapshotted application sees a file: package root', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0",
          contents: [
        d.dir("bin", [
          d.file("script.dart", """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:myapp/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
}
""")
        ])
      ]);
    });

    d.dir(appPath, [
      d.appPubspec({
        "foo": "any"
      })
    ]).create();

    pubGet(output: contains("Precompiled foo:script."));

    var pub = pubRun(args: ["foo:script"]);

    pub.stdout.expect("null");
    pub.stdout.expect(
        p.toUri(p.join(sandboxDir, "myapp/.packages")).toString());
    pub.stdout.expect(
        p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")).toString());
    schedule(() async {
      pub.stdout.expect(p.toUri(p.join(
              sandboxDir,
              cachePath,
              "hosted/localhost%58${await globalPackageServer.port}/foo-1.0.0/"
                "lib/resource.txt"))
          .toString());
    });
    pub.shouldExit(0);
  });
}
