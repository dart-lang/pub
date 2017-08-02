// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';

const MODE_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class ModeTransformer extends Transformer {
  final BarbackSettings _settings;

  ModeTransformer.asPlugin(this._settings);

  String get allowedExtensions => '.dart';

  void apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      transform.addOutput(new Asset.fromString(
          transform.primaryInput.id,
          contents.replaceAll("MODE", _settings.mode.name)));
    });
  }
}
""";

const HAS_INPUT_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class HasInputTransformer extends Transformer {
  HasInputTransformer.asPlugin();

  bool get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return Future.wait([
      transform.hasInput(new AssetId("foo", "lib/foo.dart")),
      transform.hasInput(new AssetId("foo", "lib/does/not/exist.dart"))
    ]).then((results) {
      transform.addOutput(new Asset.fromString(
          transform.primaryInput.id,
          "lib/foo.dart: \${results.first}, "
              "lib/does/not/exist.dart: \${results.last}"));
    });
  }
}
""";

const COPY_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class CopyTransformer extends Transformer {
  CopyTransformer.asPlugin();

  bool isPrimary(AssetId id) => true;

  Future apply(Transform transform) async {
    transform.addOutput(new Asset.fromString(
      transform.primaryInput.id.addExtension('.copy'),
      await transform.primaryInput.readAsString()));
  }
}
""";

const LIST_INPUTS_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class ListInputsTransformer extends AggregateTransformer {
  ListInputsTransformer.asPlugin();

  String classifyPrimary(AssetId id) => '';

  Future apply(AggregateTransform transform) async {
    var inputs = await transform.primaryInputs.toList();
    var names = inputs.map((asset) => asset.id.toString()).toList();
    names.sort();
    transform.addOutput(new Asset.fromString(
      new AssetId(transform.package, 'lib/inputs.txt'), names.join('\\n')));
  }
}
""";

main() {
  test("caches a transformed dependency", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Goodbye!';")])
    ]).validate();
  });

  test("caches a dependency transformed by its dependency", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'bar': '1.2.3'
      }, pubspec: {
        'transformers': ['bar']
      }, contents: [
        d.dir("lib", [d.file("foo.dart", "final message = 'Hello!';")])
      ]);

      builder.serve("bar", "1.2.3", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye"))
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Goodbye!';")])
    ]).validate();
  });

  test("doesn't cache an untransformed dependency", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", contents: [
        d.dir("lib", [d.file("foo.dart", "final message = 'Hello!';")])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: isNot(contains("Precompiled foo.")));

    await d.dir(appPath, [d.nothing(".pub/deps")]).validate();
  });

  test("recaches when the dependency is updated", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);

      builder.serve("foo", "1.2.4", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "See ya")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Goodbye!';")])
    ]).validate();

    // Upgrade to the new version of foo.
    await d.appDir({"foo": "1.2.4"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'See ya!';")])
    ]).validate();
  });

  test("recaches when a transitive dependency is updated", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any',
        'bar': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);

      builder.serve("bar", "5.6.7");
    });

    await d.appDir({"foo": "1.2.3"}).create();
    await pubGet(output: contains("Precompiled foo."));

    await globalPackageServer.add((builder) => builder.serve("bar", "6.0.0"));
    await pubUpgrade(output: contains("Precompiled foo."));
  });

  test("doesn't recache when an unrelated dependency is updated", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);

      builder.serve("bar", "5.6.7");
    });

    await d.appDir({"foo": "1.2.3"}).create();
    await pubGet(output: contains("Precompiled foo."));

    await globalPackageServer.add((builder) => builder.serve("bar", "6.0.0"));
    await pubUpgrade(output: isNot(contains("Precompiled foo.")));
  });

  test("caches the dependency in debug mode", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", MODE_TRANSFORMER),
          d.file("foo.dart", "final mode = 'MODE';")
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final mode = 'debug';")])
    ]).validate();
  });

  test("loads code from the cache", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);
    });

    await d.dir(appPath, [
      d.appPubspec({"foo": "1.2.3"}),
      d.dir('bin', [
        d.file('script.dart', """
          import 'package:foo/foo.dart';

          void main() => print(message);""")
      ])
    ]).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Modified!';")])
    ]).create();

    var pub = await pubRun(args: ["bin/script"]);
    expect(pub.stdout, emits("Modified!"));
    await pub.shouldExit();
  });

  test("doesn't re-transform code loaded from the cache", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);
    });

    await d.dir(appPath, [
      d.appPubspec({"foo": "1.2.3"}),
      d.dir('bin', [
        d.file('script.dart', """
          import 'package:foo/foo.dart';

          void main() => print(message);""")
      ])
    ]).create();

    await pubGet(output: contains("Precompiled foo."));

    // Manually reset the cache to its original state to prove that the
    // transformer won't be run again on it.
    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Hello!';")])
    ]).create();

    var pub = await pubRun(args: ["bin/script"]);
    expect(pub.stdout, emits("Hello!"));
    await pub.shouldExit();
  });

  // Regression test for issue 21087.
  test("hasInput works for static packages", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "void main() => print('Hello!');")
        ])
      ]);
    });

    await d.dir(appPath, [
      d.pubspec({
        "name": "myapp",
        "dependencies": {"foo": "1.2.3"},
        "transformers": ["myapp/src/transformer"]
      }),
      d.dir("lib", [
        d.dir("src", [d.file("transformer.dart", HAS_INPUT_TRANSFORMER)])
      ]),
      d.dir("web", [d.file("foo.txt", "foo")])
    ]).create();

    await pubGet(output: contains("Precompiled foo."));

    await pubServe();
    await requestShouldSucceed(
        "foo.txt", "lib/foo.dart: true, lib/does/not/exist.dart: false");
    await endPubServe();
  });

  // Regression test for issue 21810.
  test(
      "decaches when the dependency is updated to something "
      "untransformed", () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo']
      }, contents: [
        d.dir("lib", [
          d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
          d.file("foo.dart", "final message = 'Hello!';")
        ])
      ]);

      builder.serve("foo", "1.2.4", deps: {
        'barback': 'any'
      }, contents: [
        d.dir("lib", [d.file("foo.dart", "final message = 'Hello!';")])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo."));

    await d.dir(appPath, [
      d.dir(".pub/deps/debug/foo/lib",
          [d.file("foo.dart", "final message = 'Goodbye!';")])
    ]).validate();

    // Upgrade to the new version of foo.
    await d.appDir({"foo": "1.2.4"}).create();

    await pubGet(output: isNot(contains("Precompiled foo.")));

    await d.dir(appPath, [d.nothing(".pub/deps/debug/foo")]).validate();
  });

  // Regression test for https://github.com/dart-lang/pub/issues/1586.
  test("AggregateTransformers can read generated inputs from cached packages",
      () async {
    await servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve("foo", "1.2.3", deps: {
        'barback': 'any'
      }, pubspec: {
        'transformers': ['foo/copy_transformer', 'foo/list_transformer'],
      }, contents: [
        d.dir("lib", [
          d.file("hello.dart", "String get hello => 'hello';"),
          d.file("copy_transformer.dart", COPY_TRANSFORMER),
          d.file("list_transformer.dart", LIST_INPUTS_TRANSFORMER),
        ])
      ]);
    });

    await d.appDir({"foo": "1.2.3"}).create();

    await pubGet(output: contains("Precompiled foo"));

    await d.dir(appPath, [
      d.file(".pub/deps/debug/foo/lib/inputs.txt", contains('hello.dart.copy'))
    ]).validate();

    await pubServe();
    await requestShouldSucceed("packages/foo/inputs.txt", """
foo|lib/copy_transformer.dart
foo|lib/copy_transformer.dart.copy
foo|lib/hello.dart
foo|lib/hello.dart.copy
foo|lib/list_transformer.dart
foo|lib/list_transformer.dart.copy""");
    await endPubServe();
  });

  group("with --no-precompile", () {
    test("doesn't cache a transformed dependency", () async {
      await servePackages((builder) {
        builder.serveRealPackage('barback');

        builder.serve("foo", "1.2.3", deps: {
          'barback': 'any'
        }, pubspec: {
          'transformers': ['foo']
        }, contents: [
          d.dir("lib", [
            d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
            d.file("foo.dart", "final message = 'Hello!';")
          ])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.nothing(p.join(appPath, ".pub")).validate();
    });

    test("deletes the cache when the dependency is updated", () async {
      await servePackages((builder) {
        builder.serveRealPackage('barback');

        builder.serve("foo", "1.2.3", deps: {
          'barback': 'any'
        }, pubspec: {
          'transformers': ['foo']
        }, contents: [
          d.dir("lib", [
            d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
            d.file("foo.dart", "final message = 'Hello!';")
          ])
        ]);

        builder.serve("foo", "1.2.4", deps: {
          'barback': 'any'
        }, pubspec: {
          'transformers': ['foo']
        }, contents: [
          d.dir("lib", [
            d.file("transformer.dart", replaceTransformer("Hello", "See ya")),
            d.file("foo.dart", "final message = 'Hello!';")
          ])
        ]);
      });

      await d.appDir({"foo": "1.2.3"}).create();

      await pubGet(output: contains("Precompiled foo."));

      await d.dir(appPath, [
        d.dir(".pub/deps/debug/foo/lib",
            [d.file("foo.dart", "final message = 'Goodbye!';")])
      ]).validate();

      // Upgrade to the new version of foo.
      await d.appDir({"foo": "1.2.4"}).create();

      await pubGet(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.nothing(p.join(appPath, ".pub/deps/debug/foo")).validate();
    });

    test(
        "doesn't delete a cache when an unrelated dependency is "
        "updated", () async {
      await servePackages((builder) {
        builder.serveRealPackage('barback');

        builder.serve("foo", "1.2.3", deps: {
          'barback': 'any'
        }, pubspec: {
          'transformers': ['foo']
        }, contents: [
          d.dir("lib", [
            d.file("transformer.dart", replaceTransformer("Hello", "Goodbye")),
            d.file("foo.dart", "final message = 'Hello!';")
          ])
        ]);

        builder.serve("bar", "5.6.7");
      });

      await d.appDir({"foo": "1.2.3"}).create();
      await pubGet(output: contains("Precompiled foo."));

      await d.dir(appPath, [
        d.dir(".pub/deps/debug/foo/lib",
            [d.file("foo.dart", "final message = 'Goodbye!';")])
      ]).validate();

      globalPackageServer.add((builder) => builder.serve("bar", "6.0.0"));
      await pubUpgrade(
          args: ["--no-precompile"], output: isNot(contains("Precompiled")));

      await d.dir(appPath, [
        d.dir(".pub/deps/debug/foo/lib",
            [d.file("foo.dart", "final message = 'Goodbye!';")])
      ]).validate();
    });
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
