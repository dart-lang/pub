// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/exceptions.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('parse()', () {
    final sources = SystemCache().sources;

    var throwsPubspecException =
        throwsA(const TypeMatcher<SourceSpanApplicationException>());

    void expectPubspecException(
      String contents,
      void Function(Pubspec) fn, [
      String? expectedContains,
    ]) {
      var expectation = const TypeMatcher<SourceSpanApplicationException>();
      if (expectedContains != null) {
        expectation = expectation.having(
          (error) => error.message,
          'message',
          contains(expectedContains),
        );
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
      expect(
        () => Pubspec.parse('name: foo', sources, expectedName: 'bar'),
        throwsPubspecException,
      );
    });

    test(
        "eagerly throws an error if the pubspec doesn't have a name and an "
        'expected name is passed', () {
      expect(
        () => Pubspec.parse('{}', sources, expectedName: 'bar'),
        throwsPubspecException,
      );
    });

    test('allows a version constraint for dependencies', () {
      var pubspec = Pubspec.parse(
        '''
dependencies:
  foo:
    hosted:
      name: foo
      url: https://foo.com
    version: ">=1.2.3 <3.4.5"
''',
        sources,
      );

      var foo = pubspec.dependencies['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows empty version constraint', () {
      var pubspec = Pubspec.parse(
        '''
dependencies:
  foo:
    hosted:
      name: foo
      url: https://foo.com
    version: ">=1.2.3 <0.0.0"
''',
        sources,
      );

      var foo = pubspec.dependencies['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.constraint.isEmpty, isTrue);
    });

    test('allows an empty dependencies map', () {
      var pubspec = Pubspec.parse(
        '''
dependencies:
''',
        sources,
      );

      expect(pubspec.dependencies, isEmpty);
    });

    test('allows a version constraint for dev dependencies', () {
      var pubspec = Pubspec.parse(
        '''
dev_dependencies:
  foo:
    hosted:
      name: foo
      url: https://foo.com
    version: ">=1.2.3 <3.4.5"
''',
        sources,
      );

      var foo = pubspec.devDependencies['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows an empty dev dependencies map', () {
      var pubspec = Pubspec.parse(
        '''
dev_dependencies:
''',
        sources,
      );

      expect(pubspec.devDependencies, isEmpty);
    });

    test('allows a version constraint for dependency overrides', () {
      var pubspec = Pubspec.parse(
        '''
dependency_overrides:
  foo:
    hosted:
      name: foo
      url: https://foo.com
    version: ">=1.2.3 <3.4.5"
''',
        sources,
      );

      var foo = pubspec.dependencyOverrides['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.constraint.allows(Version(1, 2, 3)), isTrue);
      expect(foo.constraint.allows(Version(1, 2, 5)), isTrue);
      expect(foo.constraint.allows(Version(3, 4, 5)), isFalse);
    });

    test('allows an empty dependency overrides map', () {
      var pubspec = Pubspec.parse(
        '''
dependency_overrides:
''',
        sources,
      );

      expect(pubspec.dependencyOverrides, isEmpty);
    });

    test('allows an unknown source', () {
      var pubspec = Pubspec.parse(
        '''
dependencies:
  foo:
    unknown: blah
''',
        sources,
      );

      var foo = pubspec.dependencies['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources('unknown')));
    });

    test('allows a default source', () {
      var pubspec = Pubspec.parse(
        '''
dependencies:
  foo:
    version: 1.2.3
''',
        sources,
      );

      var foo = pubspec.dependencies['foo']!;
      expect(foo.name, equals('foo'));
      expect(foo.source, equals(sources('hosted')));
    });

    test('throws if it depends on itself', () {
      expectPubspecException(
        '''
name: myapp
dependencies:
  myapp:
    fake: ok
''',
        (pubspec) => pubspec.dependencies,
      );
    });

    test('throws if it has a dev dependency on itself', () {
      expectPubspecException(
        '''
name: myapp
dev_dependencies:
  myapp:
    fake: ok
''',
        (pubspec) => pubspec.devDependencies,
      );
    });

    test('throws if it has an override on itself', () {
      expectPubspecException(
        '''
name: myapp
dependency_overrides:
  myapp:
    fake: ok
''',
        (pubspec) => pubspec.dependencyOverrides,
      );
    });

    test("throws if the description isn't valid", () {
      expectPubspecException(
        '''
name: myapp
dependencies:
  foo:
    hosted:
      name: foo
      url: '::'
''',
        (pubspec) => pubspec.dependencies,
      );
    });

    test('throws if dependency version is not a string', () {
      expectPubspecException(
        '''
dependencies:
  foo:
    fake: ok
    version: 1.2
''',
        (pubspec) => pubspec.dependencies,
      );
    });

    test('throws if version is not a version constraint', () {
      expectPubspecException(
        '''
dependencies:
  foo:
    fake: ok
    version: not constraint
''',
        (pubspec) => pubspec.dependencies,
      );
    });

    test("throws if 'name' is not a string", () {
      expectPubspecException(
        'name: [not, a, string]',
        (pubspec) => pubspec.name,
      );
    });

    test('throws if version is not a string', () {
      expectPubspecException(
        'version: [2, 0, 0]',
        (pubspec) => pubspec.version,
        '"version" field must be a string',
      );
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
        'version: not version',
        (pubspec) => pubspec.version,
      );
    });

    test('allows comment-only files', () {
      var pubspec = Pubspec.parse(
        '''
# No external dependencies yet
# Including for completeness
# ...and hoping the spec expands to include details about author, version, etc
# See https://dart.dev/tools/pub/cmd for details
''',
        sources,
      );
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

    group('source dependencies', () {
      test('with url and name', () {
        var pubspec = Pubspec.parse(
          '''
name: pkg
dependencies:
  foo:
    hosted:
      url: https://example.org/pub/
      name: bar
''',
          sources,
        );

        var foo = pubspec.dependencies['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source.name, 'hosted');
        expect(
            ResolvedHostedDescription(
              foo.description as HostedDescription,
              sha256: null,
            ).serializeForLockfile(containingDir: null),
            {
              'url': 'https://example.org/pub/',
              'name': 'bar',
            });
      });

      test('with url only', () {
        var pubspec = Pubspec.parse(
          '''
name: pkg
environment:
  sdk: ^2.15.0
dependencies:
  foo:
    hosted:
      url: https://example.org/pub/
''',
          sources,
        );

        var foo = pubspec.dependencies['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source.name, 'hosted');
        expect(
            ResolvedHostedDescription(
              foo.description as HostedDescription,
              sha256: null,
            ).serializeForLockfile(containingDir: null),
            {
              'url': 'https://example.org/pub/',
              'name': 'foo',
            });
      });

      test('with url as string', () {
        var pubspec = Pubspec.parse(
          '''
name: pkg
environment:
  sdk: ^2.15.0
dependencies:
  foo:
    hosted: https://example.org/pub/
''',
          sources,
        );

        var foo = pubspec.dependencies['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source.name, 'hosted');
        expect(
            ResolvedHostedDescription(
              foo.description as HostedDescription,
              sha256: null,
            ).serializeForLockfile(containingDir: null),
            {
              'url': 'https://example.org/pub/',
              'name': 'foo',
            });
      });

      test('interprets string description as name for older versions', () {
        var pubspec = Pubspec.parse(
          '''
name: pkg
environment:
  sdk: ^2.14.0
dependencies:
  foo:
    hosted: bar
''',
          sources,
        );

        var foo = pubspec.dependencies['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source.name, 'hosted');
        expect(
            ResolvedHostedDescription(
              foo.description as HostedDescription,
              sha256: null,
            ).serializeForLockfile(containingDir: null),
            {
              'url': 'https://pub.dev',
              'name': 'bar',
            });
      });

      test(
        'reports helpful span when using new syntax with invalid environment',
        () {
          var pubspec = Pubspec.parse(
            '''
name: pkg
environment:
  sdk: invalid value
dependencies:
  foo:
    hosted: https://example.org/pub/
''',
            sources,
          );

          expect(
            () => pubspec.dependencies,
            throwsA(
              isA<SourceSpanApplicationException>()
                  .having((e) => e.span!.text, 'span.text', 'invalid value'),
            ),
          );
        },
      );

      test('without a description', () {
        var pubspec = Pubspec.parse(
          '''
name: pkg
dependencies:
  foo:
''',
          sources,
        );

        var foo = pubspec.dependencies['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source.name, 'hosted');
        expect(
            ResolvedHostedDescription(
              foo.description as HostedDescription,
              sha256: null,
            ).serializeForLockfile(containingDir: null),
            {
              'url': 'https://pub.dev',
              'name': 'foo',
            });
      });

      group('throws without a min SDK constraint', () {
        test('and without a name', () {
          expectPubspecException(
              '''
name: pkg
dependencies:
  foo:
    hosted:
      url: https://example.org/pub/
''',
              (pubspec) => pubspec.dependencies,
              "The 'name' key must have a string value without a minimum Dart "
                  'SDK constraint of 2.15.');
        });

        test(
          'and a hosted: <value> syntax that looks like an URI was meant',
          () {
            expectPubspecException(
              '''
name: pkg
dependencies:
  foo:
    hosted: http://pub.example.org
''',
              (pubspec) => pubspec.dependencies,
              'Using `hosted: <url>` is only supported with a minimum SDK constraint of 2.15.',
            );
          },
        );
      });
    });

    group('git dependencies', () {
      test('path must be a string', () {
        expectPubspecException(
          '''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: 12
''',
          (pubspec) => pubspec.dependencies,
        );
      });

      test('path must be relative', () {
        expectPubspecException(
          '''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: git://github.com/dart-lang/foo/bar
''',
          (pubspec) => pubspec.dependencies,
        );

        expectPubspecException(
          '''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: /foo
''',
          (pubspec) => pubspec.dependencies,
        );
      });

      test('path must be within the repository', () {
        expectPubspecException(
          '''
dependencies:
  foo:
    git:
      url: git://github.com/dart-lang/foo
      path: foo/../../bar
''',
          (pubspec) => pubspec.dependencies,
        );
      });
    });

    group('environment', () {
      test('allows an omitted environment', () {
        var pubspec = Pubspec.parse('name: testing', sources);
        expect(
          pubspec.dartSdkConstraint.effectiveConstraint,
          VersionConstraint.parse('<2.0.0'),
        );

        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test('default SDK constraint can be omitted with empty environment', () {
        var pubspec = Pubspec.parse('', sources);
        expect(
          pubspec.dartSdkConstraint.effectiveConstraint,
          VersionConstraint.parse('<2.0.0'),
        );
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test('defaults the upper constraint for the SDK', () {
        var pubspec = Pubspec.parse(
          '''
  name: test
  environment:
    sdk: ">1.0.0"
  ''',
          sources,
        );
        expect(
          pubspec.dartSdkConstraint.effectiveConstraint,
          VersionConstraint.parse('>1.0.0 <2.0.0'),
        );
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test(
          'default upper constraint for the SDK applies only if compatibile '
          'with the lower bound', () {
        var pubspec = Pubspec.parse(
          '''
  environment:
    sdk: ">3.0.0"
  ''',
          sources,
        );
        expect(
          pubspec.sdkConstraints,
          containsPair(
            'dart',
            SdkConstraint(VersionConstraint.parse('>3.0.0')),
          ),
        );
        expect(pubspec.sdkConstraints, isNot(contains('flutter')));
        expect(pubspec.sdkConstraints, isNot(contains('fuchsia')));
      });

      test("throws if the environment value isn't a map", () {
        expectPubspecException(
          'environment: []',
          (pubspec) => pubspec.sdkConstraints,
        );
      });

      test('allows a version constraint for the SDKs', () {
        var pubspec = Pubspec.parse(
          '''
environment:
  sdk: ">=1.2.3 <2.3.4"
  flutter: ^0.1.2
  fuchsia: ^5.6.7
''',
          sources,
        );
        expect(
          pubspec.sdkConstraints,
          containsPair(
            'dart',
            SdkConstraint(VersionConstraint.parse('>=1.2.3 <2.3.4')),
          ),
        );
        expect(
          pubspec.sdkConstraints,
          containsPair(
            'flutter',
            SdkConstraint(
              VersionConstraint.parse('>=0.1.2'),
              originalConstraint: VersionConstraint.parse('^0.1.2'),
            ),
          ),
        );
        expect(
          pubspec.sdkConstraints,
          containsPair(
            'fuchsia',
            SdkConstraint(VersionConstraint.parse('^5.6.7')),
          ),
        );
      });

      test("throws if the sdk isn't a string", () {
        expectPubspecException(
          'environment: {sdk: []}',
          (pubspec) => pubspec.sdkConstraints,
        );
        expectPubspecException(
          'environment: {sdk: 1.0}',
          (pubspec) => pubspec.sdkConstraints,
        );
        expectPubspecException(
          'environment: {sdk: 1.2.3, flutter: []}',
          (pubspec) => pubspec.sdkConstraints,
        );
        expectPubspecException(
          'environment: {sdk: 1.2.3, flutter: 1.0}',
          (pubspec) => pubspec.sdkConstraints,
        );
      });

      test("throws if the sdk isn't a valid version constraint", () {
        expectPubspecException(
          'environment: {sdk: "oopies"}',
          (pubspec) => pubspec.sdkConstraints,
        );
        expectPubspecException(
          'environment: {sdk: 1.2.3, flutter: "oopies"}',
          (pubspec) => pubspec.sdkConstraints,
        );
      });
    });

    group('publishTo', () {
      test('defaults to null if omitted', () {
        var pubspec = Pubspec.parse('', sources);
        expect(pubspec.publishTo, isNull);
      });

      test('throws if not a string', () {
        expectPubspecException(
          'publish_to: 123',
          (pubspec) => pubspec.publishTo,
        );
      });

      test('allows a URL', () {
        var pubspec = Pubspec.parse(
          '''
publish_to: http://example.com
''',
          sources,
        );
        expect(pubspec.publishTo, equals('http://example.com'));
      });

      test('allows none', () {
        var pubspec = Pubspec.parse(
          '''
publish_to: none
''',
          sources,
        );
        expect(pubspec.publishTo, equals('none'));
      });

      test('throws on other strings', () {
        expectPubspecException(
          'publish_to: http://bad.url:not-port',
          (pubspec) => pubspec.publishTo,
        );
      });

      test('throws on non-absolute URLs', () {
        expectPubspecException(
          'publish_to: pub.dev',
          (pubspec) => pubspec.publishTo,
        );
      });
    });

    group('executables', () {
      test('defaults to an empty map if omitted', () {
        var pubspec = Pubspec.parse('', sources);
        expect(pubspec.executables, isEmpty);
      });

      test('allows simple names for keys and most characters in values', () {
        var pubspec = Pubspec.parse(
          '''
executables:
  abcDEF-123_: "abc DEF-123._"
''',
          sources,
        );
        expect(pubspec.executables['abcDEF-123_'], equals('abc DEF-123._'));
      });

      test('throws if not a map', () {
        expectPubspecException(
          'executables: not map',
          (pubspec) => pubspec.executables,
        );
      });

      test('throws if key is not a string', () {
        expectPubspecException(
          'executables: {123: value}',
          (pubspec) => pubspec.executables,
        );
      });

      test("throws if a key isn't a simple name", () {
        expectPubspecException(
          'executables: {funny/name: ok}',
          (pubspec) => pubspec.executables,
        );
      });

      test('throws if a value is not a string', () {
        expectPubspecException(
          'executables: {command: 123}',
          (pubspec) => pubspec.executables,
        );
      });

      test('throws if a value contains a path separator', () {
        expectPubspecException(
          'executables: {command: funny_name/part}',
          (pubspec) => pubspec.executables,
        );
      });

      test('throws if a value contains a windows path separator', () {
        expectPubspecException(
          r'executables: {command: funny_name\part}',
          (pubspec) => pubspec.executables,
        );
      });

      test('uses the key if the value is null', () {
        var pubspec = Pubspec.parse(
          '''
executables:
  command:
''',
          sources,
        );
        expect(pubspec.executables['command'], equals('command'));
      });
    });

    group('pubspec overrides', () {
      Pubspec parsePubspecOverrides(String overridesContents) {
        return Pubspec.parse(
          '''
name: app
environment:
  sdk: '>=2.7.0 <3.0.0'
dependency_overrides:
  bar: 2.1.0
''',
          sources,
          overridesFileContents: overridesContents,
          overridesLocation: Uri.parse('file:///pubspec_overrides.yaml'),
        );
      }

      void expectPubspecOverridesException(
        String contents,
        void Function(Pubspec) fn, [
        String? expectedContains,
      ]) {
        var expectation = isA<SourceSpanApplicationException>();
        if (expectedContains != null) {
          expectation = expectation.having(
            (error) => error.toString(),
            'toString()',
            contains(expectedContains),
          );
        }

        var pubspec = parsePubspecOverrides(contents);
        expect(() => fn(pubspec), throwsA(expectation));
      }

      test('allows empty overrides file', () {
        var pubspec = parsePubspecOverrides('');
        expect(pubspec.dependencyOverrides['foo'], isNull);
        final bar = pubspec.dependencyOverrides['bar']!;
        expect(bar.name, equals('bar'));
        expect(bar.source, equals(sources('hosted')));
        expect(bar.constraint, VersionConstraint.parse('2.1.0'));
      });

      test('allows empty dependency_overrides section', () {
        final pubspec = parsePubspecOverrides('''
dependency_overrides:
''');
        expect(pubspec.dependencyOverrides, isEmpty);
      });

      test('parses dependencies in dependency_overrides section', () {
        final pubspec = parsePubspecOverrides('''
dependency_overrides:
  foo:
    version: 1.0.0
''');

        expect(pubspec.dependencyOverrides['bar'], isNull);

        final foo = pubspec.dependencyOverrides['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.source, equals(sources('hosted')));
        expect(foo.constraint, VersionConstraint.parse('1.0.0'));
      });

      test('throws exception with correct source references', () {
        expectPubspecOverridesException(
          '''
dependency_overrides:
  foo:
    hosted:
      name: foo
      url: '::'
''',
          (pubspecOverrides) => pubspecOverrides.dependencyOverrides,
          'Error on line 4, column 7 of ${Platform.pathSeparator}pubspec_overrides.yaml',
        );
      });

      test('throws if overrides contain invalid dependency section', () {
        expectPubspecOverridesException(
          '''
dependency_overrides: false
''',
          (pubspecOverrides) => pubspecOverrides.dependencyOverrides,
        );
      });

      test('throws if overrides contain an unknown field', () {
        expectPubspecOverridesException(
          '''
name: 'foo'
''',
          (pubspecOverrides) => pubspecOverrides.dependencyOverrides,
        );
      });
    });
  });
}
