// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

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

// TODO(nweiz): Currently scheduled_test.setUp doesn't play well with test_pub,
// since it only assigns the sandbox directory once the main test body has
// run. Fix this and move this to a real setUp call.
void setUp() {
  servePackages((builder) {
    builder.serveRealPackage('barback');

    builder.serve("foo", "1.2.3", deps: {
      'barback': 'any'
    }, contents: [
      d.dir("lib",
          [d.file("transformer.dart", replaceTransformer("Hello", "Goodbye"))])
    ]);

    builder.serve("bar", "1.2.3", deps: {
      'barback': 'any'
    }, contents: [
      d.dir("lib",
          [d.file("transformer.dart", replaceTransformer("Goodbye", "See ya"))])
    ]);

    builder.serve("baz", "1.2.3");
  });

  d.dir(appPath, [
    d.pubspec({
      "name": "myapp",
      "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
      "transformers": ["foo"]
    }),
    d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
  ]).create();

  pubGet();
}

main() {
  integration("caches a transformer snapshot", () {
    setUp();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    // Run the executable again to make sure loading the transformer from the
    // cache works.
    process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();
  });

  integration("recaches if the SDK version is out-of-date", () {
    setUp();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        // The version 0.0.1 is different than the test version 0.1.2+3.
        d.file("manifest.txt", "0.0.1\nfoo"),
        d.file("transformers.snapshot", "junk")
      ])
    ]).create();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  integration("recaches if the transformers change", () {
    setUp();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
        "transformers": ["foo", "bar"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    pubGet();
    process = pubRun(args: ['myapp']);
    process.stdout.expect("See ya!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nbar,foo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  integration("recaches if the transformer version changes", () {
    setUp();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();

    globalPackageServer.add((builder) {
      builder.serve("foo", "2.0.0", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib",
            [d.file("transformer.dart", replaceTransformer("Hello", "New"))])
      ]);
    });

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "any"},
        "transformers": ["foo"]
      })
    ]).create();

    pubUpgrade();

    process = pubRun(args: ['myapp']);
    process.stdout.expect("New!");
    process.shouldExit();

    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nfoo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
      ])
    ]).validate();
  });

  integration("recaches if a transitive dependency version changes", () {
    servePackages((builder) {
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

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3"},
        "transformers": ["foo"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    pubGet();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    globalPackageServer.add((builder) {
      builder.serve("bar", "2.0.0", contents: [
        d.dir("lib", [d.file("bar.dart", "final replacement = 'See ya';")])
      ]);
    });

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "any"},
        "transformers": ["foo"]
      })
    ]).create();

    pubUpgrade();

    process = pubRun(args: ['myapp']);
    process.stdout.expect("See ya!");
    process.shouldExit();
  });

  // Issue 21298.
  integration("doesn't recache when a transformer is removed", () {
    setUp();

    d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3", "bar": "1.2.3"},
        "transformers": ["foo", "bar"]
      }),
      d.dir("bin", [d.file("myapp.dart", "main() => print('Hello!');")])
    ]).create();

    var process = pubRun(args: ['myapp']);
    process.stdout.expect("See ya!");
    process.shouldExit();

    d.dir(appPath, [
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

    pubGet();
    process = pubRun(args: ['myapp']);
    process.stdout.expect("Goodbye!");
    process.shouldExit();

    // "bar" should still be in the manifest, since there's no reason to
    // recompile the cache.
    d.dir(appPath, [
      d.dir(".pub/transformers", [
        d.file("manifest.txt", "0.1.2+3\nbar,foo"),
        d.matcherFile("transformers.snapshot", isNot(isEmpty))
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
