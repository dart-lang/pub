// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("upgrades a snapshot when its package is upgraded", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.2.3", contents: [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await d.appDir({"foo": "any"}).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin', 'foo'),
        [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

    await globalPackageServer.add((builder) {
      builder.serve("foo", "1.2.4", contents: [
        d.dir(
            "bin", [d.file("hello.dart", "void main() => print('hello 2!');")])
      ]);
    });

    await pubUpgrade(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin', 'foo'),
        [d.file('hello.dart.snapshot', contains('hello 2!'))]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("hello 2!"));
    await process.shouldExit();
  });
}
