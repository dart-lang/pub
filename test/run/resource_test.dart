// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

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
  integration('the spawned application can load its own resource', () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("resource.txt", "hello!")
      ]),
      d.dir("bin", [
        d.file("script.dart", """
main() async {
  var resource = new Resource("package:myapp/resource.txt");

  // TODO(nweiz): Enable this when sdk#23990 is fixed.
  // print(resource.uri);

  print(await resource.readAsString());
}
""")
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  });

  integration("the spawned application can load a dependency's resource", () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file("resource.txt", "hello!")
      ])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("bin", [
        d.file("script.dart", """
main() async {
  var resource = new Resource("package:foo/resource.txt");

  // TODO(nweiz): Enable this when sdk#23990 is fixed.
  // print(resource.uri);

  print(await resource.readAsString());
}
""")
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "foo/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  });

  integration('the spawned application can load a transformed resource', () {
    serveBarback();

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
main() async {
  var resource = new Resource("package:myapp/resource.txt");

  // TODO(nweiz): Enable this when sdk#23990 is fixed.
  // print(resource.uri);

  print(await resource.readAsString());
}
""")
      ])
    ]).create();

    pubGet();
    var pub = pubRun(args: ["bin/script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  });

  integration('a snapshotted application can load a resource', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir("lib", [
          d.file("resource.txt", "hello!")
        ]),
        d.dir("bin", [
          d.file("script.dart", """
main() async {
  var resource = new Resource("package:foo/resource.txt");

  // TODO(nweiz): Enable this when sdk#23990 is fixed.
  // print(resource.uri);

  print(await resource.readAsString());
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

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "foo/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  });
}
