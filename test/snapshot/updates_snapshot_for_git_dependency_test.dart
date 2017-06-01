// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("upgrades a snapshot when a git dependency is upgraded", () async {
    await ensureGit();

    await d.git('foo.git', [
      d.pubspec({"name": "foo", "version": "0.0.1"}),
      d.dir("bin", [d.file("hello.dart", "void main() => print('Hello!');")])
    ]).create();

    await d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin', 'foo'),
        [d.file('hello.dart.snapshot', contains('Hello!'))]).validate();

    await d.git('foo.git', [
      d.dir("bin", [d.file("hello.dart", "void main() => print('Goodbye!');")])
    ]).commit();

    await pubUpgrade(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.pub', 'bin', 'foo'),
        [d.file('hello.dart.snapshot', contains('Goodbye!'))]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();
  });
}
