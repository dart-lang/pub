// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("includes .dart files from dependencies in debug mode", () async {
    await d.dir("foo", [
      d.libPubspec("foo", "0.0.1"),
      d.dir("lib", [
        d.file('foo.dart', 'foo() => print("hello");'),
        d.dir("sub", [
          d.file('bar.dart', 'bar() => print("hello");'),
        ])
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("example", [
        d.file("main.dart", 'myapp() => print("not entrypoint");'),
        d.dir(
            "sub", [d.file("main.dart", 'myapp() => print("not entrypoint");')])
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "--mode", "debug", "example"],
        output: new RegExp(r'Built \d+ files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('example', [
          d.file("main.dart", 'myapp() => print("not entrypoint");'),
          d.dir('packages', [
            d.dir('foo', [
              d.file('foo.dart', 'foo() => print("hello");'),
              d.dir("sub", [
                d.file('bar.dart', 'bar() => print("hello");'),
              ])
            ])
          ]),
          d.dir("sub", [
            d.file("main.dart", 'myapp() => print("not entrypoint");'),
            // Does *not* copy packages into subdirectories.
            d.nothing("packages")
          ])
        ])
      ])
    ]).validate();
  });
}
