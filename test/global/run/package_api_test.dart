// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('an immutable application sees a file: package config', () {
    servePackages((builder) {
      builder.serve("bar", "1.0.0");

      builder.serve("foo", "1.0.0",
          deps: {"bar": "1.0.0"},
          contents: [
        d.dir("bin", [
          d.file("script.dart", """
import 'dart:isolate';

main() async {
  print(await Isolate.packageRoot);
  print(await Isolate.packageConfig);
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:foo/resource.txt')));
  print(await Isolate.resolvePackageUri(
      Uri.parse('package:bar/resource.txt')));
}
""")
        ])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    var pub = pubRun(global: true, args: ["foo:script"]);

    pub.stdout.expect("null");

    var packageConfigPath =
        p.join(sandboxDir, cachePath, "global_packages/foo/.packages");
    pub.stdout.expect(p.toUri(packageConfigPath).toString());

    schedule(() async {
      var fooResourcePath = p.join(
          await globalPackageServer.pathInCache('foo', '1.0.0'),
          "lib/resource.txt");
      pub.stdout.expect(p.toUri(fooResourcePath).toString());
    });

    schedule(() async {
      var barResourcePath = p.join(
          await globalPackageServer.pathInCache('bar', '1.0.0'),
          "lib/resource.txt");
      pub.stdout.expect(p.toUri(barResourcePath).toString());
    });
    pub.shouldExit(0);
  });

  integration('a mutable untransformed application sees a file: package root',
      () {
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

    schedulePub(args: ["global", "activate", "-s", "path", "."]);

    var pub = pubRun(global: true, args: ["myapp:script"]);

    pub.stdout.expect("null");

    var packageConfigPath = p.join(sandboxDir, "myapp/.packages");
    pub.stdout.expect(p.toUri(packageConfigPath).toString());

    schedule(() async {
      var myappResourcePath = p.join(sandboxDir, "myapp/lib/resource.txt");
      pub.stdout.expect(p.toUri(myappResourcePath).toString());
    });

    schedule(() async {
      var fooResourcePath = p.join(sandboxDir, "foo/lib/resource.txt");
      pub.stdout.expect(p.toUri(fooResourcePath).toString());
    });
    pub.shouldExit(0);
  });

  integration('a mutable transformed application sees an http: package root',
      () {
    serveBarback();

    d.dir("foo", [
      d.libPubspec("foo", "1.0.0")
    ]).create();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": {"path": "../foo"},
          "barback": "any"
        },
        "transformers": ["myapp/src/transformer"]
      }),

      d.dir("lib/src", [
        d.file("transformer.dart", """
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
        """)
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

    schedulePub(args: ["global", "activate", "-s", "path", "."]);

    var pub = pubRun(global: true, args: ["myapp:script"]);

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
}
