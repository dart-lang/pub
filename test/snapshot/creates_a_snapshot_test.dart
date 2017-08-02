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
      builder.serve("foo", "1.2.3", contents: [
        d.dir("bin", [
          d.file("hello.dart", "void main() => print('hello!');"),
          d.file("goodbye.dart", "void main() => print('goodbye!');"),
          d.file("shell.sh", "echo shell"),
          d.dir("subdir", [d.file("sub.dart", "void main() => print('sub!');")])
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(
        output: allOf([
      contains("Precompiled foo:hello."),
      contains("Precompiled foo:goodbye.")
    ]));

    await d.dir(p.join(appPath, '.pub', 'bin'), [
      d.file('sdk-version', '0.1.2+3\n'),
      d.dir('foo', [
        d.file('hello.dart.snapshot', contains('hello!')),
        d.file('goodbye.dart.snapshot', contains('goodbye!')),
        d.nothing('shell.sh.snapshot'),
        d.nothing('subdir')
      ])
    ]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("hello!"));
    await process.shouldExit();

    process = await pubRun(args: ['foo:goodbye']);
    expect(process.stdout, emits("goodbye!"));
    await process.shouldExit();
  });
}
