// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("doesn't create a Dart 2 snapshot in Dart 1", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir('bin', [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await runPub(
        args: ["global", "activate", "foo"],
        output: allOf([contains('Precompiled foo:hello.')]));

    await d.dir(p.join(cachePath, 'global_packages', 'foo', 'bin'),
        [d.nothing('hello.dart.snapshot.dart2')]).validate();
  });

  test("creates both a Dart 1 and Dart 2 snapshot in Dart 2", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir('bin', [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await runPub(
        args: ["global", "activate", "foo"],
        output: allOf([contains('Precompiled foo:hello.')]),
        dart2: true);

    await d.dir(p.join(cachePath, 'global_packages', 'foo', 'bin'), [
      d.file('hello.dart.snapshot', contains('hello!')),
      d.file('hello.dart.snapshot.dart2', contains('hello!'))
    ]).validate();
  });

  test("creates a Dart 2 snapshot when reactivated with Dart 2", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir('bin', [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await runPub(
        args: ["global", "activate", "foo"],
        output: allOf([contains('Precompiled foo:hello.')]));
    await runPub(
        args: ["global", "activate", "foo"],
        output: allOf([contains('Precompiled foo:hello.')]),
        dart2: true);

    await d.dir(p.join(cachePath, 'global_packages', 'foo', 'bin'), [
      d.file('hello.dart.snapshot', contains('hello!')),
      d.file('hello.dart.snapshot.dart2', contains('hello!'))
    ]).validate();
  });

  test("creates a Dart 2 snapshot when run with Dart 2", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.0.0", contents: [
        d.dir('bin', [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
    });

    await runPub(
        args: ["global", "activate", "foo"],
        output: allOf([contains('Precompiled foo:hello.')]));

    var pub = await pubRun(global: true, args: ["foo:hello"], dart2: true);
    // In the real world this would just print "hello!", but since we
    // collect all output we see the precompilation messages as well.
    expect(pub.stdout, emits("Precompiling executables..."));
    expect(pub.stdout, emitsThrough("hello!"));
    await pub.shouldExit();

    await d.dir(p.join(cachePath, 'global_packages', 'foo', 'bin'), [
      d.file('hello.dart.snapshot', contains('hello!')),
      d.file('hello.dart.snapshot.dart2', contains('hello!'))
    ]).validate();
  });
}
