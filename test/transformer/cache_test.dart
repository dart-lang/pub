// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const REPLACE_FROM_LIBRARY_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';
import 'package:bar/bar.dart';

class ReplaceTransformer extends Transformer {
  ReplaceTransformer.asPlugin();

  String get allowedExtensions => '.dart';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      transform.addOutput(new Asset.fromString(
          transform.primaryInput.id,
          contents.replaceAll("Hello", replacement)));
    });
  }
}
""";

main() {
  setUp(() async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye"))
        ])
      ]);

      builder.serve("bar", "1.2.3", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Goodbye", "See ya"))
        ])
      ]);

      builder.serve("baz", "1.2.3");
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
        "transformers": ["foo"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    await pubGet();
  });

  test("caches a transformer snapshot", () async {
    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    // Run the executable again to make sure loading the transformer from the
    // cache works.
    process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();
  });

  test("recaches if the SDK version is out-of-date", () async {
    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        // The version 0.0.1 is different than the test version 0.1.2+3.
        d.file("manifest.txt", "0.0.1\nfoo"),
        d.file("transformers.snapshot", "junk")
      ])
    ]).create();

    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  test("recaches if the transformers change", () async {
    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
        "transformers": ["foo", "bar"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    await pubGet();
    process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("See ya!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nbar,foo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  test("recaches if the transformer version changes", () async {
    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    await globalPackageServer.add((builder) {
      builder.serve("foo", "2.0.0", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib",
            [d.file("transformer.dart", replaceTransformer("Hello", "New"))])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "any"},
        "transformers": ["foo"]
      })
    ]).create();

    await pubUpgrade();

    process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("New!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  test("recaches if a transitive dependency version changes", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any',
        'bar': 'any'
      }, contents: [
        d.dir("lib",
            [d.file("transformer.dart", REPLACE_FROM_LIBRARY_TRANSFORMER)])
      ]);

      builder.serve("bar", "1.2.3", contents: [
        d.dir("lib", [d.file("bar.dart", "final replacement = 'Goodbye';")])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3"},
        "transformers": ["foo"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    await pubGet();

    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    await globalPackageServer.add((builder) {
      builder.serve("bar", "2.0.0", contents: [
        d.dir("lib", [d.file("bar.dart", "final replacement = 'See ya';")])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "any"},
        "transformers": ["foo"]
      })
    ]).create();

    await pubUpgrade();

    process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("See ya!"));
    await process.shouldExit();
  });

  // Issue 21298.
  test("doesn't recache when a transformer is removed", () async {
    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
        "transformers": ["foo", "bar"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    var process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("See ya!"));
    await process.shouldExit();

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {
          "foo": "1.2.3",
          // Add a new dependency to trigger another "pub get". This works
          // around issue 20498.
          "baz": "1.2.3"
        },
        "transformers": ["foo"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    await pubGet();
    process = await pubRun(args: ['myapp']);
    expect(process.stdout, emits("Goodbye!"));
    await process.shouldExit();

    // "bar" should still be in the manifest, since there's no reason to
    // recompile the cache.
    await d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nbar,foo"),
        d.file("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });
}

String replaceTransformer(String input, String output) {
  return """
import 'dart:async';

import 'package:barback/barback.dart';

class ReplaceTransformer extends Transformer {
  ReplaceTransformer.asPlugin();

  String get allowedExtensions => '.dart';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      transform.addOutput(new Asset.fromString(
          transform.primaryInput.id,
          contents.replaceAll("$input", "$output")));
    });
  }
}
""";
}
