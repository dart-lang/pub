// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/compiler.dart';
import 'package:pub/src/package_name.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source.dart';
import 'package:pub/src/source_registry.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

class MockSource extends Source {
  final String name = "mock";

  BoundSource bind(SystemCache cache) =>
      throw new UnsupportedError("Cannot download mock packages.");

  PackageRef parseRef(String name, description, {String containingPath}) {
    if (description != 'ok') throw new FormatException('Bad');
    return new PackageRef(name, this, description);
  }

  PackageId parseId(String name, Version version, description) =>
      new PackageId(name, this, version, description);

  bool descriptionsEqual(description1, description2) =>
      description1 == description2;

  int hashDescription(description) => description.hashCode;

  String packageName(description) => 'foo';
}

main() {
  group('parse()', () {
    var sources = new SourceRegistry();
    sources.register(new MockSource());

    var throwsPubspecException = throwsA(new isInstanceOf<PubspecException>());

    expectPubspecException(String contents, fn(Pubspec pubspec),
        [String expectedContains]) {
      var expectation = throwsPubspecException;
      if (expectedContains != null) {
        expectation = throwsA(allOf(new isInstanceOf<PubspecException>(),
            predicate((error) => error.message.contains(expectedContains))));
      }

      var pubspec = new Pubspec.parse(contents, sources);
      expect(() => fn(pubspec), expectation);
    }

    test("doesn't eagerly throw an error for an invalid field", () {
      // Shouldn't throw an error.
      new Pubspec.parse('version: not a semver', sources);
    });

    test(
        "eagerly throws an error if the pubspec name doesn't match the "
        "expected name", () {
      expect(() => new Pubspec.parse("name: foo", sources, expectedName: 'bar'),
          throwsPubspecException);
    });

    test(
        "eagerly throws an error if the pubspec doesn't have a name and an "
        "expected name is passed", () {
      expect(() => new Pubspec.parse("{}", sources, expectedName: 'bar'),
          throwsPubspecException);
    });

    test("allows a version constraint for dependencies", () {
      var pubspec = new Pubspec.parse(
          '''
dependencies:
  foo:
    mock: ok
    version: ">=1.2.3 <3.4.5"
''',
          sources);

      var foo = pubspec.dependencies[0];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(new Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(new Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(new Version(3, 4, 5)), isFalse);
    });

    test("allows an empty dependencies map", () {
      var pubspec = new Pubspec.parse(
          '''
dependencies:
''',
          sources);

      expect(pubspec.dependencies, isEmpty);
    });

    test("allows a version constraint for dev dependencies", () {
      var pubspec = new Pubspec.parse(
          '''
dev_dependencies:
  foo:
    mock: ok
    version: ">=1.2.3 <3.4.5"
''',
          sources);

      var foo = pubspec.devDependencies[0];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(new Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(new Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(new Version(3, 4, 5)), isFalse);
    });

    test("allows an empty dev dependencies map", () {
      var pubspec = new Pubspec.parse(
          '''
dev_dependencies:
''',
          sources);

      expect(pubspec.devDependencies, isEmpty);
    });

    test("allows a version constraint for dependency overrides", () {
      var pubspec = new Pubspec.parse(
          '''
dependency_overrides:
  foo:
    mock: ok
    version: ">=1.2.3 <3.4.5"
''',
          sources);

      var foo = pubspec.dependencyOverrides[0];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(new Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(new Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(new Version(3, 4, 5)), isFalse);
    });

    test("allows an empty dependency overrides map", () {
      var pubspec = new Pubspec.parse(
          '''
dependency_overrides:
''',
          sources);

      expect(pubspec.dependencyOverrides, isEmpty);
    });

    test("allows an unknown source", () {
      var pubspec = new Pubspec.parse(
          '''
dependencies:
  foo:
    unknown: blah
''',
          sources);

      var foo = pubspec.dependencies[0];
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources['unknown']));
    });

    test("allows a default source", () {
      var pubspec = new Pubspec.parse(
          '''
dependencies:
  foo:
    version: 1.2.3
''',
          sources);

      var foo = pubspec.dependencies[0];
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources['hosted']));
    });

    test("throws if a package is in dependencies and dev_dependencies", () {
      expectPubspecException(
          '''
dependencies:
  foo:
    mock: ok
dev_dependencies:
  foo:
    mock: ok
''', (pubspec) {
        // This check only triggers if both [dependencies] and [devDependencies]
        // are accessed.
        pubspec.dependencies;
        pubspec.devDependencies;
      });
    });

    test("throws if it dependes on itself", () {
      expectPubspecException(
          '''
name: myapp
dependencies:
  myapp:
    mock: ok
''',
          (pubspec) => pubspec.dependencies);
    });

    test("throws if it has a dev dependency on itself", () {
      expectPubspecException(
          '''
name: myapp
dev_dependencies:
  myapp:
    mock: ok
''',
          (pubspec) => pubspec.devDependencies);
    });

    test("throws if it has an override on itself", () {
      expectPubspecException(
          '''
name: myapp
dependency_overrides:
  myapp:
    mock: ok
''',
          (pubspec) => pubspec.dependencyOverrides);
    });

    test("throws if the description isn't valid", () {
      expectPubspecException(
          '''
dependencies:
  foo:
    mock: bad
''',
          (pubspec) => pubspec.dependencies);
    });

    test("throws if dependency version is not a string", () {
      expectPubspecException(
          '''
dependencies:
  foo:
    mock: ok
    version: 1.2
''',
          (pubspec) => pubspec.dependencies);
    });

    test("throws if version is not a version constraint", () {
      expectPubspecException(
          '''
dependencies:
  foo:
    mock: ok
    version: not constraint
''',
          (pubspec) => pubspec.dependencies);
    });

    test("throws if 'name' is not a string", () {
      expectPubspecException(
          'name: [not, a, string]', (pubspec) => pubspec.name);
    });

    test("throws if version is not a string", () {
      expectPubspecException('version: [2, 0, 0]', (pubspec) => pubspec.version,
          '"version" field must be a string');
    });

    test("throws if version is malformed (looking like a double)", () {
      expectPubspecException(
          'version: 2.1',
          (pubspec) => pubspec.version,
          '"version" field must have three numeric components: major, minor, '
          'and patch. Instead of "2.1", consider "2.1.0"');
    });

    test("throws if version is malformed (looking like an int)", () {
      expectPubspecException(
          'version: 2',
          (pubspec) => pubspec.version,
          '"version" field must have three numeric components: major, minor, '
          'and patch. Instead of "2", consider "2.0.0"');
    });

    test("throws if version is not a version", () {
      expectPubspecException(
          'version: not version', (pubspec) => pubspec.version);
    });

    test("throws if transformers isn't a list", () {
      expectPubspecException(
          'transformers: "not list"',
          (pubspec) => pubspec.transformers,
          '"transformers" field must be a list');
    });

    test("throws if a transformer isn't a string or map", () {
      expectPubspecException(
          'transformers: [12]',
          (pubspec) => pubspec.transformers,
          'A transformer must be a string or map.');
    });

    test("throws if a transformer's configuration isn't a map", () {
      expectPubspecException(
          'transformers: [{pkg: 12}]',
          (pubspec) => pubspec.transformers,
          "A transformer's configuration must be a map.");
    });

    test(
        "throws if a transformer's configuration contains an unknown "
        "reserved key at the top level", () {
      expectPubspecException(
          '''
name: pkg
transformers: [{pkg: {\$key: "value"}}]''',
          (pubspec) => pubspec.transformers,
          'Invalid transformer config: Unknown reserved field.');
    });

    test(
        "doesn't throw if a transformer's configuration contains a "
        "non-top-level key beginning with a dollar sign", () {
      var pubspec = new Pubspec.parse(
          '''
name: pkg
transformers:
- pkg: {outer: {\$inner: value}}
''',
          sources);

      var pkg = pubspec.transformers[0].single;
      expect(pkg.configuration["outer"]["\$inner"], equals("value"));
    });

    test("throws if the \$include value is not a string or list", () {
      expectPubspecException(
          '''
name: pkg
transformers:
- pkg: {\$include: 123}''',
          (pubspec) => pubspec.transformers,
          'Invalid transformer config: "\$include" field must be a string or '
          'list.');
    });

    test("throws if the \$include list contains a non-string", () {
      expectPubspecException(
          '''
name: pkg
transformers:
- pkg: {\$include: ["ok", 123, "alright", null]}''',
          (pubspec) => pubspec.transformers,
          'Invalid transformer config: "\$include" field may contain only '
          'strings.');
    });

    test("throws if the \$exclude value is not a string or list", () {
      expectPubspecException(
          '''
name: pkg
transformers:
- pkg: {\$exclude: 123}''',
          (pubspec) => pubspec.transformers,
          'Invalid transformer config: "\$exclude" field must be a string or '
          'list.');
    });

    test("throws if the \$exclude list contains a non-string", () {
      expectPubspecException(
          '''
name: pkg
transformers:
- pkg: {\$exclude: ["ok", 123, "alright", null]}''',
          (pubspec) => pubspec.transformers,
          'Invalid transformer config: "\$exclude" field may contain only '
          'strings.');
    });

    test("throws if a transformer is not from a dependency", () {
      expectPubspecException(
          '''
name: pkg
transformers: [foo]
''',
          (pubspec) => pubspec.transformers,
          '"foo" is not a dependency.');
    });

    test("allows a transformer from a normal dependency", () {
      var pubspec = new Pubspec.parse(
          '''
name: pkg
dependencies:
  foo:
    mock: ok
transformers:
- foo''',
          sources);

      expect(pubspec.transformers[0].single.id.package, equals("foo"));
    });

    test("allows a transformer from a dev dependency", () {
      var pubspec = new Pubspec.parse(
          '''
name: pkg
dev_dependencies:
  foo:
    mock: ok
transformers:
- foo''',
          sources);

      expect(pubspec.transformers[0].single.id.package, equals("foo"));
    });

    test("allows a transformer from a dependency override", () {
      var pubspec = new Pubspec.parse(
          '''
name: pkg
dependency_overrides:
  foo:
    mock: ok
transformers:
- foo''',
          sources);

      expect(pubspec.transformers[0].single.id.package, equals("foo"));
    });

    test("allows comment-only files", () {
      var pubspec = new Pubspec.parse(
          '''
# No external dependencies yet
# Including for completeness
# ...and hoping the spec expands to include details about author, version, etc
# See http://www.dartlang.org/docs/pub-package-manager/ for details
''',
          sources);
      expect(pubspec.version, equals(Version.none));
      expect(pubspec.dependencies, isEmpty);
    });

    test("throws a useful error for unresolvable path dependencies", () {
      expectPubspecException(
          '''
name: pkg
dependencies:
  from_path: {path: non_local_path}
''',
          (pubspec) => pubspec.dependencies,
          '"non_local_path" is a relative path, but this isn\'t a local '
          'pubspec.');
    });

    group("environment", () {
      test("allows an omitted environment", () {
        var pubspec = new Pubspec.parse('', sources);
        expect(pubspec.dartSdkConstraint, equals(VersionConstraint.any));
        expect(pubspec.flutterSdkConstraint, isNull);
      });

      test("throws if the environment value isn't a map", () {
        expectPubspecException(
            'environment: []', (pubspec) => pubspec.dartSdkConstraint);
      });

      test("allows a version constraint for the SDKs", () {
        var pubspec = new Pubspec.parse(
            '''
environment:
  sdk: ">=1.2.3 <2.3.4"
  flutter: ^0.1.2
''',
            sources);
        expect(pubspec.dartSdkConstraint,
            equals(new VersionConstraint.parse(">=1.2.3 <2.3.4")));
        expect(pubspec.flutterSdkConstraint,
            equals(new VersionConstraint.parse("^0.1.2")));
      });

      test("throws if the sdk isn't a string", () {
        expectPubspecException(
            'environment: {sdk: []}', (pubspec) => pubspec.dartSdkConstraint);
        expectPubspecException(
            'environment: {sdk: 1.0}', (pubspec) => pubspec.dartSdkConstraint);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: []}',
            (pubspec) => pubspec.dartSdkConstraint);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: 1.0}',
            (pubspec) => pubspec.dartSdkConstraint);
      });

      test("throws if the sdk isn't a valid version constraint", () {
        expectPubspecException('environment: {sdk: "oopies"}',
            (pubspec) => pubspec.dartSdkConstraint);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: "oopies"}',
            (pubspec) => pubspec.dartSdkConstraint);
      });
    });

    group("publishTo", () {
      test("defaults to null if omitted", () {
        var pubspec = new Pubspec.parse('', sources);
        expect(pubspec.publishTo, isNull);
      });

      test("throws if not a string", () {
        expectPubspecException(
            'publish_to: 123', (pubspec) => pubspec.publishTo);
      });

      test("allows a URL", () {
        var pubspec = new Pubspec.parse(
            '''
publish_to: http://example.com
''',
            sources);
        expect(pubspec.publishTo, equals("http://example.com"));
      });

      test("allows none", () {
        var pubspec = new Pubspec.parse(
            '''
publish_to: none
''',
            sources);
        expect(pubspec.publishTo, equals("none"));
      });

      test("throws on other strings", () {
        expectPubspecException('publish_to: http://bad.url:not-port',
            (pubspec) => pubspec.publishTo);
      });
    });

    group("executables", () {
      test("defaults to an empty map if omitted", () {
        var pubspec = new Pubspec.parse('', sources);
        expect(pubspec.executables, isEmpty);
      });

      test("allows simple names for keys and most characters in values", () {
        var pubspec = new Pubspec.parse(
            '''
executables:
  abcDEF-123_: "abc DEF-123._"
''',
            sources);
        expect(pubspec.executables['abcDEF-123_'], equals('abc DEF-123._'));
      });

      test("throws if not a map", () {
        expectPubspecException(
            'executables: not map', (pubspec) => pubspec.executables);
      });

      test("throws if key is not a string", () {
        expectPubspecException(
            'executables: {123: value}', (pubspec) => pubspec.executables);
      });

      test("throws if a key isn't a simple name", () {
        expectPubspecException(
            'executables: {funny/name: ok}', (pubspec) => pubspec.executables);
      });

      test("throws if a value is not a string", () {
        expectPubspecException(
            'executables: {command: 123}', (pubspec) => pubspec.executables);
      });

      test("throws if a value contains a path separator", () {
        expectPubspecException('executables: {command: funny_name/part}',
            (pubspec) => pubspec.executables);
      });

      test("throws if a value contains a windows path separator", () {
        expectPubspecException(r'executables: {command: funny_name\part}',
            (pubspec) => pubspec.executables);
      });

      test("uses the key if the value is null", () {
        var pubspec = new Pubspec.parse(
            '''
executables:
  command:
''',
            sources);
        expect(pubspec.executables['command'], equals('command'));
      });
    });

    group("web", () {
      test("can be empty", () {
        var pubspec = new Pubspec.parse('web: {}', sources);
        expect(pubspec.webCompiler, isEmpty);
      });

      group("compiler", () {
        test("defaults to an empty map if omitted", () {
          var pubspec = new Pubspec.parse('', sources);
          expect(pubspec.webCompiler, isEmpty);
        });

        test("defaults to an empty map if web is null", () {
          var pubspec = new Pubspec.parse('web:', sources);
          expect(pubspec.webCompiler, isEmpty);
        });

        test("defaults to an empty map if compiler is null", () {
          var pubspec = new Pubspec.parse('web: {compiler:}', sources);
          expect(pubspec.webCompiler, isEmpty);
        });

        test("allows simple names for keys and valid compilers in values", () {
          var pubspec = new Pubspec.parse(
              '''
web:
  compiler:
    abcDEF-123_: none
    debug: dartdevc
    release: dart2js
''',
              sources);
          expect(pubspec.webCompiler['abcDEF-123_'], equals(Compiler.none));
          expect(pubspec.webCompiler['debug'], equals(Compiler.dartDevc));
          expect(pubspec.webCompiler['release'], equals(Compiler.dart2JS));
        });

        test("throws if not a map", () {
          expectPubspecException(
              'web: {compiler: dartdevc}', (pubspec) => pubspec.webCompiler);
          expectPubspecException(
              'web: {compiler: [dartdevc]}', (pubspec) => pubspec.webCompiler);
        });

        test("throws if key is not a string", () {
          expectPubspecException('web: {compiler: {123: dartdevc}}',
              (pubspec) => pubspec.webCompiler);
        });

        test("throws if a value is not a supported compiler", () {
          expectPubspecException('web: {compiler: {debug: frog}}',
              (pubspec) => pubspec.webCompiler);
        });

        test("throws if the value is null", () {
          expectPubspecException(
              'web: {compiler: {debug: }}', (pubspec) => pubspec.webCompiler);
        });
      });
    });

    group("features", () {
      test("can be null", () {
        var pubspec = new Pubspec.parse('features:', sources);
        expect(pubspec.features, isEmpty);
      });

      test("throws if it's not a map", () {
        expectPubspecException('features: 12', (pubspec) => pubspec.features);
      });

      test("throws if it has non-string keys", () {
        expectPubspecException(
            'features: {1: {}}', (pubspec) => pubspec.features);
      });

      test("throws if a key isn't a Dart identifier", () {
        expectPubspecException(
            'features: {foo-bar: {}}', (pubspec) => pubspec.features);
      });

      test("allows null values", () {
        var pubspec = new Pubspec.parse(
            '''
features:
  foobar:
''',
            sources);
        expect(pubspec.features, contains('foobar'));

        var feature = pubspec.features['foobar'];
        expect(feature.name, equals('foobar'));
        expect(feature.onByDefault, isTrue);
        expect(feature.dependencies, isEmpty);
      });

      test("throws if the value isn't a map", () {
        expectPubspecException(
            'features: {foobar: 1}', (pubspec) => pubspec.features);
      });

      test("throws if the value's dependencies aren't valid", () {
        expectPubspecException(
            '''
features:
  foobar:
    dependencies:
      baz: not a version range
''',
            (pubspec) => pubspec.features);
      });

      test("throws if the default value isn't a boolean", () {
        expectPubspecException(
            'features: {foobar: {default: 12}}', (pubspec) => pubspec.features);
      });

      test("allows a default boolean", () {
        var pubspec =
            new Pubspec.parse('features: {foobar: {default: false}}', sources);

        expect(pubspec.features, contains('foobar'));
        expect(pubspec.features['foobar'].onByDefault, isFalse);
      });

      test("parses valid dependency specifications", () {
        var pubspec = new Pubspec.parse(
            '''
features:
  foobar:
    dependencies:
      baz: 1.0.0
      qux: ^2.0.0
''',
            sources);

        expect(pubspec.features, contains('foobar'));

        var feature = pubspec.features['foobar'];
        expect(feature.name, equals('foobar'));
        expect(feature.onByDefault, isTrue);
        expect(feature.dependencies, hasLength(2));

        expect(feature.dependencies.first.name, equals(equals('baz')));
        expect(feature.dependencies.first.constraint,
            equals(new Version(1, 0, 0)));
        expect(feature.dependencies.last.name, equals('qux'));
        expect(feature.dependencies.last.constraint,
            equals(new VersionConstraint.parse('^2.0.0')));
      });
    });
  });
}
