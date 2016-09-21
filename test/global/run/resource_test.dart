// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('the spawned application can load its own resource', () {
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

    schedulePub(args: ["global", "activate", "foo"]);

    var pub = pubRun(global: true, args: ["foo:script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  },
      skip: "Issue https://github.com/dart-lang/pub/issues/1446");

  integration("the spawned application can load a dependency's resource", () {
    servePackages((builder) {
      builder.serve("bar", "1.0.0", contents: [
        d.dir("lib", [
          d.file("resource.txt", "hello!")
        ])
      ]);

      builder.serve("foo", "1.0.0", deps: {
        "bar": "any"
      }, contents: [
        d.dir("bin", [
          d.file("script.dart", """
main() async {
  var resource = new Resource("package:bar/resource.txt");

  // TODO(nweiz): Enable this when sdk#23990 is fixed.
  // print(resource.uri);

  print(await resource.readAsString());
}
""")
        ])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);

    var pub = pubRun(global: true, args: ["foo:script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  },
      skip: "Issue https://github.com/dart-lang/pub/issues/1446");

  integration('a mutable application can load its own resource', () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
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
    ]).create();

    schedulePub(args: ["global", "activate", "--source", "path", "../foo"]);

    var pub = pubRun(global: true, args: ["foo:script"]);

    // TODO(nweiz): Enable this when sdk#23990 is fixed.
    // pub.stdout.expect(p.toUri(p.join(sandboxDir, "myapp/lib/resource.txt")));

    pub.stdout.expect("hello!");
    pub.shouldExit(0);
  },
      skip: "Issue https://github.com/dart-lang/pub/issues/1446");
}
