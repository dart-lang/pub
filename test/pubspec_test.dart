// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/package_name.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/sdk.dart';
import 'package:pub/src/source.dart';
import 'package:pub/src/source_registry.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

class FakeSource extends Source {
  @override
  final String name = 'fake';

  @override
  BoundSource bind(SystemCache cache) =>
      throw UnsupportedError('Cannot download fake packages.');

  @override
  PackageRef parseRef(String name, description, {String containingPath}) {
    if (description != 'ok') throw FormatException('Bad');
    return PackageRef(name, this, description);
  }

  @override
  PackageId parseId(String name, Version version, description,
          {String containingPath}) =>
      PackageId(name, this, version, description);

  @override
  bool descriptionsEqual(description1, description2) =>
      description1 == description2;

  @override
  int hashDescription(description) => description.hashCode;

  String packageName(description) => 'foo';
}

void main() {
  group('parse()', () {
    var sources = SourceRegistry();
    sources.register(FakeSource());

    var throwsPubspecException = throwsA(const TypeMatcher<PubspecException>());

    void expectPubspecException(String contents, void Function(Pubspec) fn,
        [String expectedContains]) {
      var expectation = const TypeMatcher<PubspecException>();
      if (expectedContains != null) {
        expectation = expectation.having(
            (error) => error.message, 'message', contains(expectedContains));
      }

      var pubspec = Pubspec.parse(contents, sources);
      expect(() => fn(pubspec), throwsA(expectation));
    }

    test("doesn't eagerly throw an error for an invalid field", () {
      // Shouldn't throw an error.
      Pubspec.parse('version: not a semver', sources);
    });

    test(
        "eagerly throws an error if the pubspec name doesn't match the "
        'expected name', () {
      expect(() => Pubspec.parse('name: foo', sources, expectedName: 'bar'),
          throwsPubspecException);
    });

    test(
        "eagerly throws an error if the pubspec doesn't have a name and an "
        'expected name is passed', () {
      expect(() => Pubspec.parse('{}', sources, expectedName: 'bar'),
          throwsPubspecException);
    });

    test('allows a version constraint for dependencies', () {
      var pubspec = Pubspec.parse('''
dependencies:
  foo:
    fake: ok
    version: ">=1.2.3 <3.4.5"
''', sources);

      var foo = pubspec.dependencies['foo'];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows an empty dependencies map', () {
      var pubspec = Pubspec.parse('''
dependencies:
''', sources);

      expect(pubspec.dependencies, isEmpty);
    });

    test('allows a version constraint for dev dependencies', () {
      var pubspec = Pubspec.parse('''
dev_dependencies:
  foo:
    fake: ok
    version: ">=1.2.3 <3.4.5"
''', sources);

      var foo = pubspec.devDependencies['foo'];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows an empty dev dependencies map', () {
      var pubspec = Pubspec.parse('''
dev_dependencies:
''', sources);

      expect(pubspec.devDependencies, isEmpty);
    });

    test('allows a version constraint for dependency overrides', () {
      var pubspec = Pubspec.parse('''
dependency_overrides:
  foo:
    fake: ok
    version: ">=1.2.3 <3.4.5"
''', sources);

      var foo = pubspec.dependencyOverrides['foo'];
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows an empty dependency overrides map', () {
      var pubspec = Pubspec.parse('''
dependency_overrides:
''', sources);

      expect(pubspec.dependencyOverrides, isEmpty);
    });

    test('allows an unknown source', () {
      var pubspec = Pubspec.parse('''
dependencies:
  foo:
    unknown: blah
''', sources);

      var foo = pubspec.dependencies['foo'];
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources['unknown']));
    });

    test('allows a default source', () {
      var pubspec = Pubspec.parse('''
dependencies:
  foo:
    version: 1.2.3
''', sources);

      var foo = pubspec.dependencies['foo'];
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources['hosted']));
    });

    test('throws if it dependes on itself', () {
      expectPubspecException('''
name: myapp
dependencies:
  myapp:
    fake: ok
''', (pubspec) => pubspec.dependencies);
    });

    test('throws if it has a dev dependency on itself', () {
      expectPubspecException('''
name: myapp
dev_dependencies:
  myapp:
    fake: ok
''', (pubspec) => pubspec.devDependencies);
    });

    test('throws if it has an override on itself', () {
      expectPubspecException('''
name: myapp
dependency_overrides:
  myapp:
    fake: ok
''', (pubspec) => pubspec.dependencyOverrides);
    });

    test("throws if the description isn't valid", () {
      expectPubspecException('''
dependencies:
  foo:
    fake: bad
''', (pubspec) => pubspec.dependencies);
    });

    test('throws if dependency version is not a string', () {
      expectPubspecException('''
dependencies:
  foo:
    fake: ok
    version: 1.2
''', (pubspec) => pubspec.dependencies);
    });

    test('throws if version is not a version constraint', () {
      expectPubspecException('''
dependencies:
  foo:
    fake: ok
    version: not constraint
''', (pubspec) => pubspec.dependencies);
    });

    test("throws if 'name' is not a string", () {
      expectPubspecException(
          'name: [not, a, string]', (pubspec) => pubspec.name);
    });

    test('throws if version is not a string', () {
      expectPubspecException('version: [2, 0, 0]', (pubspec) => pubspec.version,
          '"version" field must be a string');
    });

    test('throws if version is malformed (looking like a double)', () {
      expectPubspecException(
          'version: 2.1',
          (pubspec) => pubspec.version,
          '"version" field must have three numeric components: major, minor, '
              'and patch. Instead of "2.1", consider "2.1.0"');
    });

    test('throws if version is malformed (looking like an int)', () {
      expectPubspecException(
          'version: 2',
          (pubspec) => pubspec.version,
          '"version" field must have three numeric components: major, minor, '
              'and patch. Instead of "2", consider "2.0.0"');
    });

    test('throws if version is not a version', () {
      expectPubspecException(
          'version: not version', (pubspec) => pubspec.version);
    });

    test('allows comment-only files', () {
      var pubspec = Pubspec.parse('''
# No external dependencies yet
# Including for completeness
# ...and hoping the spec expands to include details about author, version, etc
# See https://dart.dev/tools/pub/cmd for details
''', sources);
      expect(pubspec.version, equals(Version.none));
      expect(pubspec.dependencies, isEmpty);
    });

    test('throws a useful error for unresolvable path dependencies', () {
      expectPubspecException(
          '''
name: pkg
dependencies:
  from_path: {path: non_local_path}
''',
          (pubspec) => pubspec.dependencies,
          'Invalid description in the "pkg" pubspec on the "from_path" '
              'dependency: "non_local_path" is a relative path, but this isn\'t a '
              'local pubspec.');
    });

    group('git dependencies', () {
      test('path must be a string', () {
        expectPubspecException('''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: 12
''', (pubspec) => pubspec.dependencies);
      });

      test('path must be relative', () {
        expectPubspecException('''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: git://github.com/dart-lang/foo/bar
''', (pubspec) => pubspec.dependencies);

        expectPubspecException('''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: /foo
''', (pubspec) => pubspec.dependencies);
      });

      test('path must be within the repository', () {
        expectPubspecException('''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: foo/../../bar
''', (pubspec) => pubspec.dependencies);
      });
    });

    group('environment', () {
      /// Checking for the default SDK constraint based on the current SDK.
      void expectDefaultSdkConstraint(Pubspec pubspec) {
        var sdkVersionString = sdk.version.toString();
        if (sdkVersionString.startsWith('2.0.0') && sdk.version.isPreRelease) {
          expect(
              pubspec.sdkConstraints,
              containsPair(
                  'dart',
                  VersionConstraint.parse(
                      '${pubspec.sdkConstraints["dart"]} <=$sdkVersionString')));
        } else {
          expect(
              pubspec.sdkConstraints,
              containsPair(
                  'dart',
                  VersionConstraint.parse(
                      "${pubspec.sdkConstraints["dart"]} <2.0.0")));
        }
      }

      test('allows an omitted environment', () {
        var pubspec = Pubspec.parse('name: testing', sources);
        expectDefaultSdkConstraint(pubspec);
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test('default SDK constraint can be omitted with empty environment', () {
        var pubspec = Pubspec.parse('', sources);
        expectDefaultSdkConstraint(pubspec);
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test('defaults the upper constraint for the SDK', () {
        var pubspec = Pubspec.parse('''
  name: test
  environment:
    sdk: ">1.0.0"
  ''', sources);
        expectDefaultSdkConstraint(pubspec);
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test(
          'default upper constraint for the SDK applies only if compatibile '
          'with the lower bound', () {
        var pubspec = Pubspec.parse('''
  environment:
    sdk: ">3.0.0"
  ''', sources);
        expect(pubspec.sdkConstraints,
            containsPair('dart', VersionConstraint.parse('>3.0.0')));
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test("throws if the environment value isn't a map", () {
        expectPubspecException(
            'environment: []', (pubspec) => pubspec.sdkConstraints);
      });

      test('allows a version constraint for the SDKs', () {
        var pubspec = Pubspec.parse('''
environment:
  sdk: ">=1.2.3 <2.3.4"
  flutter: ^0.1.2
  fuchsia: ^5.6.7
''', sources);
        expect(pubspec.sdkConstraints,
            containsPair('dart', VersionConstraint.parse('>=1.2.3 <2.3.4')));
        expect(pubspec.sdkConstraints,
            containsPair('flutter', VersionConstraint.parse('^0.1.2')));
        expect(pubspec.sdkConstraints,
            containsPair('fuchsia', VersionConstraint.parse('^5.6.7')));
      });

      test("throws if the sdk isn't a string", () {
        expectPubspecException(
            'environment: {sdk: []}', (pubspec) => pubspec.sdkConstraints);
        expectPubspecException(
            'environment: {sdk: 1.0}', (pubspec) => pubspec.sdkConstraints);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: []}',
            (pubspec) => pubspec.sdkConstraints);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: 1.0}',
            (pubspec) => pubspec.sdkConstraints);
      });

      test("throws if the sdk isn't a valid version constraint", () {
        expectPubspecException('environment: {sdk: "oopies"}',
            (pubspec) => pubspec.sdkConstraints);
        expectPubspecException('environment: {sdk: 1.2.3, flutter: "oopies"}',
            (pubspec) => pubspec.sdkConstraints);
      });
    });

    group('publishTo', () {
      test('defaults to null if omitted', () {
        var pubspec = Pubspec.parse('', sources);
        expect(pubspec.publishTo, isNull);
      });

      test('throws if not a string', () {
        expectPubspecException(
            'publish_to: 123', (pubspec) => pubspec.publishTo);
      });

      test('allows a URL', () {
        var pubspec = Pubspec.parse('''
publish_to: http://example.com
''', sources);
        expect(pubspec.publishTo, equals('http://example.com'));
      });

      test('allows none', () {
        var pubspec = Pubspec.parse('''
publish_to: none
''', sources);
        expect(pubspec.publishTo, equals('none'));
      });

      test('throws on other strings', () {
        expectPubspecException('publish_to: http://bad.url:not-port',
            (pubspec) => pubspec.publishTo);
      });

      test('throws on non-absolute URLs', () {
        expectPubspecException(
            'publish_to: pub.dartlang.org', (pubspec) => pubspec.publishTo);
      });
    });

    group('executables', () {
      test('defaults to an empty map if omitted', () {
        var pubspec = Pubspec.parse('', sources);
        expect(pubspec.executables, isEmpty);
      });

      test('allows simple names for keys and most characters in values', () {
        var pubspec = Pubspec.parse('''
executables:
  abcDEF-123_: "abc DEF-123._"
''', sources);
        expect(pubspec.executables['abcDEF-123_'], equals('abc DEF-123._'));
      });

      test('throws if not a map', () {
        expectPubspecException(
            'executables: not map', (pubspec) => pubspec.executables);
      });

      test('throws if key is not a string', () {
        expectPubspecException(
            'executables: {123: value}', (pubspec) => pubspec.executables);
      });

      test("throws if a key isn't a simple name", () {
        expectPubspecException(
            'executables: {funny/name: ok}', (pubspec) => pubspec.executables);
      });

      test('throws if a value is not a string', () {
        expectPubspecException(
            'executables: {command: 123}', (pubspec) => pubspec.executables);
      });

      test('throws if a value contains a path separator', () {
        expectPubspecException('executables: {command: funny_name/part}',
            (pubspec) => pubspec.executables);
      });

      test('throws if a value contains a windows path separator', () {
        expectPubspecException(r'executables: {command: funny_name\part}',
            (pubspec) => pubspec.executables);
      });

      test('uses the key if the value is null', () {
        var pubspec = Pubspec.parse('''
executables:
  command:
''', sources);
        expect(pubspec.executables['command'], equals('command'));
      });
    });

    group('features', () {
      test('can be null', () {
        var pubspec = Pubspec.parse('features:', sources);
        expect(pubspec.features, isEmpty);
      });

      test("throws if it's not a map", () {
        expectPubspecException('features: 12', (pubspec) => pubspec.features);
      });

      test('throws if it has non-string keys', () {
        expectPubspecException(
            'features: {1: {}}', (pubspec) => pubspec.features);
      });

      test("throws if a key isn't a Dart identifier", () {
        expectPubspecException(
            'features: {foo-bar: {}}', (pubspec) => pubspec.features);
      });

      test('allows null values', () {
        var pubspec = Pubspec.parse('''
features:
  foobar:
''', sources);
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
        expectPubspecException('''
features:
  foobar:
    dependencies:
      baz: not a version range
''', (pubspec) => pubspec.features);
      });

      test("throws if the environment value isn't a map", () {
        expectPubspecException(
            'features: {foobar: 1}', (pubspec) => pubspec.features);
      });

      test('allows a valid environment', () {
        var pubspec = Pubspec.parse('''
features:
  foobar:
    environment:
      sdk: ^1.0.0
      flutter: ^2.0.0
      fuchsia: ^3.0.0
''', sources);

        expect(pubspec.features, contains('foobar'));

        var feature = pubspec.features['foobar'];
        expect(feature.sdkConstraints,
            containsPair('dart', VersionConstraint.parse('^1.0.0')));
        expect(feature.sdkConstraints,
            containsPair('flutter', VersionConstraint.parse('^2.0.0')));
        expect(feature.sdkConstraints,
            containsPair('fuchsia', VersionConstraint.parse('^3.0.0')));
      });

      test("throws if the default value isn't a boolean", () {
        expectPubspecException(
            'features: {foobar: {default: 12}}', (pubspec) => pubspec.features);
      });

      test('allows a default boolean', () {
        var pubspec =
            Pubspec.parse('features: {foobar: {default: false}}', sources);

        expect(pubspec.features, contains('foobar'));
        expect(pubspec.features['foobar'].onByDefault, isFalse);
      });

      test('parses valid dependency specifications', () {
        var pubspec = Pubspec.parse('''
features:
  foobar:
    dependencies:
      baz: 1.0.0
      qux: ^2.0.0
''', sources);

        expect(pubspec.features, contains('foobar'));

        var feature = pubspec.features['foobar'];
        expect(feature.name, equals('foobar'));
        expect(feature.onByDefault, isTrue);
        expect(feature.dependencies, hasLength(2));

        expect(feature.dependencies.first.name, equals(equals('baz')));
        expect(feature.dependencies.first.constraint, equals(Version(1, 0, 0)));
        expect(feature.dependencies.last.name, equals('qux'));
        expect(feature.dependencies.last.constraint,
            equals(VersionConstraint.parse('^2.0.0')));
      });

      group('requires', () {
        test('can be null', () {
          var pubspec =
              Pubspec.parse('features: {foobar: {requires: null}}', sources);
          expect(pubspec.features['foobar'].requires, isEmpty);
        });

        test('must be a list', () {
          expectPubspecException('features: {foobar: {requires: baz}, baz: {}}',
              (pubspec) => pubspec.features);
        });

        test('must be a string list', () {
          expectPubspecException('features: {foobar: {requires: [12]}}',
              (pubspec) => pubspec.features);
        });

        test('must refer to features that exist in the pubspec', () {
          expectPubspecException('features: {foobar: {requires: [baz]}}',
              (pubspec) => pubspec.features);
        });
      });
    });
  });
}
