// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const BROKEN_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class BrokenTransformer extends Transformer {
  BrokenTransformer.asPlugin();

  // This file intentionally has a syntax error so that any attempt to load it
  // will crash.
""";

main() {
  // Regression test for issue 20917.
  test("snapshots the transformed version of an executable", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", contents: [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "barback": "any"},
        "transformers": ["myapp"]
      }),
      d.dir("lib", [d.file("transformer.dart", BROKEN_TRANSFORMER)])
    ]).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
    ]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("hello!"));
    await process.shouldExit();
  });
}
