// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('loads package imports in a dependency', () {
    d.dir("foo", [
      d.libPubspec("foo", "1.0.0"),
      d.dir("lib", [
        d.file('foo.dart', "final value = 'foobar';")
      ]),
      d.dir("bin", [
        d.file("bar.dart", """
import "package:foo/foo.dart";

main() => print(value);
""")
      ])
    ]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    var pub = pubRun(args: ["foo:bar"], shouldGetFirst: true);
    pub.stdout.expect("foobar");
    pub.shouldExit();
  });
}
