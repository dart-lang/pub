// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/lock_file.dart';
import 'package:pub/src/package_name.dart';
import 'package:pub/src/source.dart';
import 'package:pub/src/source_registry.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

class MockSource extends Source {
  final String name = 'mock';

  BoundSource bind(SystemCache cache) =>
      throw new UnsupportedError("Cannot download mock packages.");

  PackageRef parseRef(String name, description, {String containingPath}) {
    if (!description.endsWith(' desc')) throw new FormatException('Bad');
    return new PackageRef(name, this, description);
  }

  PackageId parseId(String name, Version version, description) {
    if (!description.endsWith(' desc')) throw new FormatException('Bad');
    return new PackageId(name, this, version, description);
  }

  bool descriptionsEqual(description1, description2) =>
      description1 == description2;

  int hashDescription(description) => description.hashCode;

  String packageName(String description) {
    // Strip off ' desc'.
    return description.substring(0, description.length - 5);
  }
}

main() {
  var sources = new SourceRegistry();
  var mockSource = new MockSource();
  sources.register(mockSource);

  group('LockFile', () {
    group('parse()', () {
      test('returns an empty lockfile if the contents are empty', () {
        var lockFile = new LockFile.parse('', sources);
        expect(lockFile.packages.length, equals(0));
      });

      test('returns an empty lockfile if the contents are whitespace', () {
        var lockFile = new LockFile.parse('  \t\n  ', sources);
        expect(lockFile.packages.length, equals(0));
      });

      test('parses a series of package descriptions', () {
        var lockFile = new LockFile.parse('''
packages:
  bar:
    version: 1.2.3
    source: mock
    description: bar desc
  foo:
    version: 2.3.4
    source: mock
    description: foo desc
''', sources);

        expect(lockFile.packages.length, equals(2));

        var bar = lockFile.packages['bar'];
        expect(bar.name, equals('bar'));
        expect(bar.version, equals(new Version(1, 2, 3)));
        expect(bar.source, equals(mockSource));
        expect(bar.description, equals('bar desc'));

        var foo = lockFile.packages['foo'];
        expect(foo.name, equals('foo'));
        expect(foo.version, equals(new Version(2, 3, 4)));
        expect(foo.source, equals(mockSource));
        expect(foo.description, equals('foo desc'));
      });

      test("allows an unknown source", () {
        var lockFile = new LockFile.parse('''
packages:
  foo:
    source: bad
    version: 1.2.3
    description: foo desc
''', sources);
        var foo = lockFile.packages['foo'];
        expect(foo.source, equals(sources['bad']));
      });

      test("allows an empty dependency map", () {
        var lockFile = new LockFile.parse('''
packages:
''', sources);
        expect(lockFile.packages, isEmpty);
      });

      test("allows an old-style SDK constraint", () {
        var lockFile = new LockFile.parse('sdk: ">=1.2.3 <4.0.0"', sources);
        expect(lockFile.dartSdkConstraint,
            equals(new VersionConstraint.parse('>=1.2.3 <4.0.0')));
        expect(lockFile.flutterSdkConstraint, isNull);
      });

      test("allows new-style SDK constraints", () {
        var lockFile = new LockFile.parse('''
sdks:
  dart: ">=1.2.3 <4.0.0"
  flutter: ^0.1.2
''', sources);
        expect(lockFile.dartSdkConstraint,
            equals(new VersionConstraint.parse('>=1.2.3 <4.0.0')));
        expect(lockFile.flutterSdkConstraint,
            equals(new VersionConstraint.parse('^0.1.2')));
      });

      test("throws if the top level is not a map", () {
        expect(() {
          new LockFile.parse('''
not a map
''', sources);
        }, throwsFormatException);
      });

      test("throws if the contents of 'packages' is not a map", () {
        expect(() {
          new LockFile.parse('''
packages: not a map
''', sources);
        }, throwsFormatException);
      });

      test("throws if the version is missing", () {
        expect(() {
          new LockFile.parse('''
packages:
  foo:
    source: mock
    description: foo desc
''', sources);
        }, throwsFormatException);
      });

      test("throws if the version is invalid", () {
        expect(() {
          new LockFile.parse('''
packages:
  foo:
    version: vorpal
    source: mock
    description: foo desc
''', sources);
        }, throwsFormatException);
      });

      test("throws if the source is missing", () {
        expect(() {
          new LockFile.parse('''
packages:
  foo:
    version: 1.2.3
    description: foo desc
''', sources);
        }, throwsFormatException);
      });

      test("throws if the description is missing", () {
        expect(() {
          new LockFile.parse('''
packages:
  foo:
    version: 1.2.3
    source: mock
''', sources);
        }, throwsFormatException);
      });

      test("throws if the description is invalid", () {
        expect(() {
          new LockFile.parse('''
packages:
  foo:
    version: 1.2.3
    source: mock
    description: foo desc is bad
''', sources);
        }, throwsFormatException);
      });

      test("throws if the old-style SDK constraint isn't a string", () {
        expect(() => new LockFile.parse('sdk: 1.0', sources),
            throwsFormatException);
      });

      test("throws if the old-style SDK constraint is invalid", () {
        expect(() => new LockFile.parse('sdk: oops', sources),
            throwsFormatException);
      });

      test("throws if the sdks field isn't a map", () {
        expect(() => new LockFile.parse('sdks: oops', sources),
            throwsFormatException);
      });

      test("throws if an sdk constraint isn't a string", () {
        expect(() => new LockFile.parse('sdks: {dart: 1.0}', sources),
            throwsFormatException);
        expect(() {
          new LockFile.parse('sdks: {dart: 1.0.0, flutter: 1.0}', sources);
        }, throwsFormatException);
      });

      test("throws if an sdk constraint is invalid", () {
        expect(() => new LockFile.parse('sdks: {dart: oops}', sources),
            throwsFormatException);
        expect(() {
          new LockFile.parse('sdks: {dart: 1.0.0, flutter: oops}', sources);
        }, throwsFormatException);
      });

      test("ignores extra stuff in file", () {
        new LockFile.parse('''
extra:
  some: stuff
packages:
  foo:
    bonus: not used
    version: 1.2.3
    source: mock
    description: foo desc
''', sources);
      });
    });

    test('serialize() dumps the lockfile to YAML', () {
      var lockfile = new LockFile([
        new PackageId(
            'foo', mockSource, new Version.parse('1.2.3'), 'foo desc'),
        new PackageId('bar', mockSource, new Version.parse('3.2.1'), 'bar desc')
      ]);

      expect(
          loadYaml(lockfile.serialize(null)),
          equals({
            'sdks': {'dart': 'any'},
            'packages': {
              'foo': {
                'version': '1.2.3',
                'source': 'mock',
                'description': 'foo desc'
              },
              'bar': {
                'version': '3.2.1',
                'source': 'mock',
                'description': 'bar desc'
              }
            }
          }));
    });
  });
}
