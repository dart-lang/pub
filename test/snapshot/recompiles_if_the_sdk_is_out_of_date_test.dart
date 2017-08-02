// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("creates a snapshot for an immediate dependency's executables",
      () async {
    await servePackages((builder) {
      builder.serve("foo", "5.6.7", contents: [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await d.appDir({"foo": "5.6.7"}).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.dir('foo', [d.outOfDateSnapshot('hello.dart.snapshot')])
    ]).create();

    var process = await pubRun(args: ['foo:hello']);

    // In the real world this would just print "hello!", but since we collect
    // all output we see the precompilation messages as well.
    expect(process.stdout, emits("Precompiling executables..."));
    expect(process.stdout, emitsThrough("hello!"));
    await process.shouldExit();

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.file('sdk-version', '0.1.2+3\n'),
      d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
    ]).validate();
  });
}
