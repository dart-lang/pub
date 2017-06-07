// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  group("with --no-precompile,", () {
    test("doesn't create a new snapshot", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');"),
            d.file("goodbye.dart", "void main() => print('goodbye!');"),
            d.file("shell.sh", "echo shell"),
            d.dir(
                "subdir", [d.file("sub.dart", "void main() => print('sub!');")])
          ])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.nothing(p.join(appPath, '.pub')).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();

      process = await pubRun(args: ['foo:goodbye']);
      expect(process.stdout, emits("goodbye!"));
      await process.shouldExit();
    });

    test("deletes a snapshot when its package is upgraded", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.appDir({"foo": "any"}).create();

      await pubGet(output: contains("Precompiled foo:hello."));

      await d.dir(p.join(appPath, '.pub', 'bin', 'foo'),
          [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

      await globalPackageServer.add((builder) {
        builder.serve("foo", "1.2.4", contents: [
          d.dir("bin",
              [d.file("hello.dart", "void main() => print('hello 2!');")])
        ]);
      });

      await pubUpgrade(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.nothing(p.join(appPath, '.pub', 'bin', 'foo')).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello 2!"));
      await process.shouldExit();
    });

    test(
        "doesn't delete a snapshot when no dependencies of a package "
        "have changed", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", deps: {
          "bar": "any"
        }, contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
        builder.serve("bar", "1.2.3");
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(output: contains("Precompiled foo:hello."));

      await pubUpgrade(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.dir(p.join(appPath, '.pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
      ]).validate();
    });
  });
}
