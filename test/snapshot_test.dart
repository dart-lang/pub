// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  group("creates a snapshot", () {
    test("for an immediate dependency", () async {
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
          output: allOf([
        contains("Precompiled foo:hello."),
        contains("Precompiled foo:goodbye.")
      ]));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
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

    test("for an immediate dependency that's also transitive", () async {
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
        builder.serve("bar", "1.2.3", deps: {"foo": "1.2.3"});
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          output: allOf([
        contains("Precompiled foo:hello."),
        contains("Precompiled foo:goodbye.")
      ]));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
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

    test("of the transformed version of an executable", () async {
      await servePackages((builder) {
        builder.serveRealPackage('barback');

        builder.serve("foo", "1.2.3", deps: {
          "barback": "any"
        }, pubspec: {
          'transformers': ['foo']
        }, contents: [
          d.dir("lib", [
            d.file("foo.dart", """
            import 'dart:async';

            import 'package:barback/barback.dart';

            class ReplaceTransformer extends Transformer {
              ReplaceTransformer.asPlugin();

              String get allowedExtensions => '.dart';

              Future apply(Transform transform) {
                return transform.primaryInput.readAsString().then((contents) {
                  transform.addOutput(new Asset.fromString(transform.primaryInput.id,
                      contents.replaceAll("REPLACE ME", "hello!")));
                });
              }
            }
          """)
          ]),
          d.dir("bin", [
            d.file("hello.dart", """
            final message = 'REPLACE ME';

            void main() => print(message);
          """),
          ])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(output: contains("Precompiled foo:hello."));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();
    });

    group("again if", () {
      test("its package is updated", () async {
        await servePackages((builder) {
          builder.serve("foo", "1.2.3", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello!');")])
          ]);
        });

        await d.appDir({"foo": "any"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

        await globalPackageServer.add((builder) {
          builder.serve("foo", "1.2.4", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello 2!');")])
          ]);
        });

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello 2!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("hello 2!"));
        await process.shouldExit();
      });

      test("a dependency of its package is updated", () async {
        await servePackages((builder) {
          builder.serve("foo", "1.2.3", pubspec: {
            "dependencies": {"bar": "any"}
          }, contents: [
            d.dir("bin", [
              d.file("hello.dart", """
            import 'package:bar/bar.dart';

            void main() => print(message);
          """)
            ])
          ]);
          builder.serve("bar", "1.2.3", contents: [
            d.dir("lib", [d.file("bar.dart", "final message = 'hello!';")])
          ]);
        });

        await d.appDir({"foo": "any"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

        await globalPackageServer.add((builder) {
          builder.serve("bar", "1.2.4", contents: [
            d.dir("lib", [d.file("bar.dart", "final message = 'hello 2!';")]),
          ]);
        });

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('hello 2!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("hello 2!"));
        await process.shouldExit();
      });

      test("a git dependency of its package is updated", () async {
        await ensureGit();

        await d.git('foo.git', [
          d.pubspec({"name": "foo", "version": "0.0.1"}),
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('Hello!');")])
        ]).create();

        await d.appDir({
          "foo": {"git": "../foo.git"}
        }).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('Hello!'))]).validate();

        await d.git('foo.git', [
          d.dir("bin",
              [d.file("hello.dart", "void main() => print('Goodbye!');")])
        ]).commit();

        await pubUpgrade(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
            [d.file('hello.dart.snapshot', contains('Goodbye!'))]).validate();

        var process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits("Goodbye!"));
        await process.shouldExit();
      });

      test("the SDK is out of date", () async {
        await servePackages((builder) {
          builder.serve("foo", "5.6.7", contents: [
            d.dir("bin",
                [d.file("hello.dart", "void main() => print('hello!');")])
          ]);
        });

        await d.appDir({"foo": "5.6.7"}).create();

        await pubGet(output: contains("Precompiled foo:hello."));

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.dir('foo', [d.outOfDateSnapshot('hello.dart.snapshot')])
        ]).create();

        var process = await pubRun(args: ['foo:hello']);

        // In the real world this would just print "hello!", but since we collect
        // all output we see the precompilation messages as well.
        expect(process.stdout, emits("Precompiling executables..."));
        expect(process.stdout, emitsThrough("hello!"));
        await process.shouldExit();

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.file('sdk-version', '0.1.2+3\n'),
          d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
        ]).validate();
      });
    });
  });

  // Regression test for #1127.
  test("doesn't load irrelevant transformers", () async {
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
      d.dir("lib", [
        d.file("transformer.dart", """
            import 'dart:async';

            import 'package:barback/barback.dart';

            class BrokenTransformer extends Transformer {
              BrokenTransformer.asPlugin();

              // This file intentionally has a syntax error so that any attempt to load it
              // will crash.
          """)
      ])
    ]).create();

    await pubGet(output: contains("Precompiled foo:hello."));

    await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
      d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
    ]).validate();

    var process = await pubRun(args: ['foo:hello']);
    expect(process.stdout, emits("hello!"));
    await process.shouldExit();
  });

  group("doesn't create a snapshot", () {
    test("when no dependencies of a package have changed", () async {
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

      await pubUpgrade(output: isNot(contains("Precompiled foo:hello.")));

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
      ]).validate();
    }, skip: true);

    test("for a package that depends on the entrypoint", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", deps: {
          'bar': '1.2.3'
        }, contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
        builder.serve("bar", "1.2.3", deps: {'myapp': 'any'});
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet();

      // No local cache should be created, since all dependencies transitively
      // depend on the entrypoint.
      await d.nothing(p.join(appPath, '.dart_tool', 'pub', 'bin')).validate();
    });

    test("for a path dependency", () async {
      await d.dir("foo", [
        d.libPubspec("foo", "1.2.3"),
        d.dir("bin", [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ])
      ]).create();

      await d.appDir({
        "foo": {"path": "../foo"}
      }).create();

      await pubGet();

      await d.nothing(p.join(appPath, '.dart_tool', 'pub', 'bin')).validate();
    });

    test("for a transitive dependency", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", deps: {'bar': '1.2.3'});
        builder.serve("bar", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet();

      await d
          .nothing(p.join(appPath, '.dart_tool', 'pub', 'bin', 'bar'))
          .validate();
    });
  });

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

      await d.nothing(p.join(appPath, '.dart_tool', 'pub')).validate();

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

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'),
          [d.file('hello.dart.snapshot', contains('hello!'))]).validate();

      await globalPackageServer.add((builder) {
        builder.serve("foo", "1.2.4", contents: [
          d.dir("bin",
              [d.file("hello.dart", "void main() => print('hello 2!');")])
        ]);
      });

      await pubUpgrade(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d
          .nothing(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'))
          .validate();

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

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.file('sdk-version', '0.1.2+3\n'),
        d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
      ]).validate();
    }, skip: true);
  });

  test("prints errors for broken snapshot compilation", () async {
    await servePackages((builder) {
      builder.serve("foo", "1.2.3", contents: [
        d.dir("bin", [
          d.file("hello.dart", "void main() { no closing brace"),
          d.file("goodbye.dart", "void main() { no closing brace"),
        ])
      ]);
      builder.serve("bar", "1.2.3", contents: [
        d.dir("bin", [
          d.file("hello.dart", "void main() { no closing brace"),
          d.file("goodbye.dart", "void main() { no closing brace"),
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3", "bar": "1.2.3"}).create();

    // This should still have a 0 exit code, since installation succeeded even
    // if precompilation didn't.
    await pubGet(
        error: allOf([
          contains("Failed to precompile foo:hello"),
          contains("Failed to precompile foo:goodbye"),
          contains("Failed to precompile bar:hello"),
          contains("Failed to precompile bar:goodbye")
        ]),
        exitCode: 0);

    await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
      d.file('sdk-version', '0.1.2+3\n'),
      d.dir('foo', [
        d.nothing('hello.dart.snapshot'),
        d.nothing('goodbye.dart.snapshot')
      ]),
      d.dir('bar', [
        d.nothing('hello.dart.snapshot'),
        d.nothing('goodbye.dart.snapshot')
      ])
    ]).validate();
  });

  group("migrates the old-style cache", () {
    test("when installing packages", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.dir(appPath, [
        d.appPubspec({"foo": "1.2.3"}),

        // Simulate an old-style cache directory.
        d.dir(".pub", [d.file("junk", "junk")])
      ]).create();

      await pubGet(output: contains("Precompiled foo:hello."));

      await d.dir(appPath, [d.nothing(".pub")]).validate();

      await d.dir(p.join(appPath, '.dart_tool', 'pub'), [
        d.file('junk', 'junk'),
        d.dir('bin', [
          d.file('sdk-version', '0.1.2+3\n'),
          d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
        ])
      ]).validate();
    });

    test("when running executables", () async {
      await servePackages((builder) {
        builder.serve("foo", "1.2.3", contents: [
          d.dir(
              "bin", [d.file("hello.dart", "void main() => print('hello!');")])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(output: contains("Precompiled foo:hello."));

      // Move the directory to the old location to simulate it being created by an
      // older version of pub.
      renameDir(p.join(d.sandbox, appPath, '.dart_tool', 'pub'),
          p.join(d.sandbox, appPath, '.pub'));

      await d.dir(appPath, [
        d.dir(".pub", [d.file("junk", "junk")])
      ]).create();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits("hello!"));
      await process.shouldExit();

      await d.dir(p.join(appPath, '.dart_tool', 'pub'), [
        d.file('junk', 'junk'),
        d.dir('bin', [
          d.file('sdk-version', '0.1.2+3\n'),
          d.dir('foo', [d.file('hello.dart.snapshot', contains('hello!'))])
        ])
      ]).validate();
    });
  });
}
