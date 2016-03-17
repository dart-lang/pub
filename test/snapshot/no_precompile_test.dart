// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  group("with --no-precompile,", () {
    integration("doesn't create a new snapshot", () {
      servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');"),
            d.file("goodbye.dart", "void main() => print('goodbye!');"),
            d.file("shell.sh", "echo shell"),
            d.dir("subdir", [
              d.file("sub.dart", "void main() => print('sub!');")
            ])
          ])
        ]);
      });

      d.appDir({"foo": "1.2.3"}).create();

      pubGet(args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      d.nothing(p.join(appPath, '.pub')).validate();

      var process = pubRun(args: ['foo:hello']);
      process.stdout.expect("hello!");
      process.shouldExit();

      process = pubRun(args: ['foo:goodbye']);
      process.stdout.expect("goodbye!");
      process.shouldExit();
    });

    integration("deletes a snapshot when its package is upgraded", () {
      servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');")
          ])
        ]);
      });

      d.appDir({"foo": "any"}).create();

      pubGet(output: contains("Precompiled foo:hello."));

      d.dir(p.join(appPath, '.pub', 'bin', 'foo'), [
        d.matcherFile('hello.dart.snapshot', contains('hello!'))
      ]).validate();

      globalPackageServer.add((builder) {
        builder.serve("foo", "1.2.4", contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello 2!');")
          ])
        ]);
      });

      pubUpgrade(
          args: ["--no-precompile"],
          output: isNot(contains("Precompiled")));

      d.nothing(p.join(appPath, '.pub', 'bin', 'foo')).validate();

      var process = pubRun(args: ['foo:hello']);
      process.stdout.expect("hello 2!");
      process.shouldExit();
    });

    integration("doesn't delete a snapshot when no dependencies of a package "
        "have changed", () {
      servePackages((builder) {
        builder.serve("foo", "1.2.3", deps: {"bar": "any"}, contents: [
          d.dir("bin", [
            d.file("hello.dart", "void main() => print('hello!');")
          ])
        ]);
        builder.serve("bar", "1.2.3");
      });

      d.appDir({"foo": "1.2.3"}).create();

      pubGet(output: contains("Precompiled foo:hello."));

      pubUpgrade(
          args: ["--no-precompile"],
          output: isNot(contains("Precompiled")));

      d.dir(p.join(appPath, '.pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [d.matcherFile('hello.dart.snapshot', contains('hello!'))])
      ]).validate();
    });
  });
}
