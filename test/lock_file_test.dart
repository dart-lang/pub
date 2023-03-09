// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/lock_file.dart';
import 'package:pub/src/package_name.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart' hide Description;
import 'package:yaml/yaml.dart';

void main() {
  final cache = SystemCache();
  final sources = cache.sources;
  group('LockFile', () {
    group('parse()', () {
      test('returns an empty lockfile if the contents are empty', () {
        var lockFile = LockFile.parse('', sources);
        expect(lockFile.packages.length, equals(0));
      });

      test('returns an empty lockfile if the contents are whitespace', () {
        var lockFile = LockFile.parse('  \t\n  ', sources);
        expect(lockFile.packages.length, equals(0));
      });

      test('parses a series of package descriptions', () {
        var lockFile = LockFile.parse(
          '''
packages:
  bar:
    version: 1.2.3
    source: hosted
    description:
      name: bar
      url: https://bar.com
  foo:
    version: 2.3.4
    source: hosted
    description:
      name: foo
      url: https://foo.com
''',
          cache.sources,
        );

        expect(lockFile.packages.length, equals(2));

        var bar = lockFile.packages['bar']!;
        expect(bar.name, equals('bar'));
        expect(bar.version, equals(Version(1, 2, 3)));
        expect(bar.source, equals(cache.hosted));
        expect(
          (bar.description.description as HostedDescription).url,
          equals('https://bar.com'),
        );

        var foo = lockFile.packages['foo']!;
        expect(foo.name, equals('foo'));
        expect(foo.version, equals(Version(2, 3, 4)));
        expect(foo.source, equals(cache.hosted));
        expect(
          (foo.description.description as HostedDescription).url,
          equals('https://foo.com'),
        );
      });

      test('allows an unknown source', () {
        var lockFile = LockFile.parse(
          '''
packages:
  foo:
    source: bad
    version: 1.2.3
    description: foo desc
''',
          cache.sources,
        );
        var foo = lockFile.packages['foo']!;
        expect(foo.source, equals(sources('bad')));
      });

      test('allows an empty dependency map', () {
        var lockFile = LockFile.parse(
          '''
packages:
''',
          sources,
        );
        expect(lockFile.packages, isEmpty);
      });

      test('allows an old-style SDK constraint', () {
        var lockFile = LockFile.parse('sdk: ">=1.2.3 <4.0.0"', sources);
        expect(
          lockFile.sdkConstraints,
          containsPair('dart', VersionConstraint.parse('>=1.2.3 <4.0.0')),
        );
        expect(lockFile.sdkConstraints, isNot(contains('flutter')));
        expect(lockFile.sdkConstraints, isNot(contains('fuchsia')));
      });

      test('allows new-style SDK constraints', () {
        var lockFile = LockFile.parse(
          '''
sdks:
  dart: ">=1.2.3 <4.0.0"
  flutter: ^0.1.2
  fuchsia: ^5.6.7
''',
          sources,
        );
        expect(
          lockFile.sdkConstraints,
          containsPair('dart', VersionConstraint.parse('>=1.2.3 <4.0.0')),
        );
        expect(
          lockFile.sdkConstraints,
          containsPair('flutter', VersionConstraint.parse('^0.1.2')),
        );
        expect(
          lockFile.sdkConstraints,
          containsPair('fuchsia', VersionConstraint.parse('^5.6.7')),
        );
      });

      test('throws if the top level is not a map', () {
        expect(
          () {
            LockFile.parse(
              '''
not a map
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test("throws if the contents of 'packages' is not a map", () {
        expect(
          () {
            LockFile.parse(
              '''
packages: not a map
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test('throws if the version is missing', () {
        expect(
          () {
            LockFile.parse(
              '''
packages:
  foo:
    source: fake
    description: foo desc
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test('throws if the version is invalid', () {
        expect(
          () {
            LockFile.parse(
              '''
packages:
  foo:
    version: vorpal
    source: fake
    description: foo desc
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test('throws if the source is missing', () {
        expect(
          () {
            LockFile.parse(
              '''
packages:
  foo:
    version: 1.2.3
    description: foo desc
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test('throws if the description is missing', () {
        expect(
          () {
            LockFile.parse(
              '''
packages:
  foo:
    version: 1.2.3
    source: fake
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test('throws if the description is invalid', () {
        expect(
          () {
            LockFile.parse(
              '''
packages:
  foo:
    version: 1.2.3
    source: hosted
    description: foam
''',
              sources,
            );
          },
          throwsFormatException,
        );
      });

      test("throws if the old-style SDK constraint isn't a string", () {
        expect(
          () => LockFile.parse('sdk: 1.0', sources),
          throwsFormatException,
        );
      });

      test('throws if the old-style SDK constraint is invalid', () {
        expect(
          () => LockFile.parse('sdk: oops', sources),
          throwsFormatException,
        );
      });

      test("throws if the sdks field isn't a map", () {
        expect(
          () => LockFile.parse('sdks: oops', sources),
          throwsFormatException,
        );
      });

      test("throws if an sdk constraint isn't a string", () {
        expect(
          () => LockFile.parse('sdks: {dart: 1.0}', sources),
          throwsFormatException,
        );
        expect(
          () {
            LockFile.parse('sdks: {dart: 1.0.0, flutter: 1.0}', sources);
          },
          throwsFormatException,
        );
      });

      test('throws if an sdk constraint is invalid', () {
        expect(
          () => LockFile.parse('sdks: {dart: oops}', sources),
          throwsFormatException,
        );
        expect(
          () {
            LockFile.parse('sdks: {dart: 1.0.0, flutter: oops}', sources);
          },
          throwsFormatException,
        );
      });

      test('Reads pub.dartlang.org as pub.dev in hosted descriptions', () {
        final lockfile = LockFile.parse(
          '''
packages:
  characters:
    dependency: transitive
    description:
      name: characters
      url: "https://pub.dartlang.org"
    source: hosted
    version: "1.2.1"
  retry:
    dependency: transitive
    description:
      name: retry
      url: "https://pub.dev"
      sha256:
    source: hosted
    version: "1.0.0"
''',
          sources,
        );
        void expectComesFromPubDev(String name) {
          final description = lockfile.packages[name]!.description.description
              as HostedDescription;
          expect(
            description.url,
            'https://pub.dev',
          );
        }

        expectComesFromPubDev('characters');
        expectComesFromPubDev('retry');
      });

      test('Complains about malformed content-hashes', () {
        expect(
          () => LockFile.parse(
            '''
packages:
  retry:
    dependency: transitive
    description:
      name: retry
      url: "https://pub.dev"
      sha256: abc # Not long enough
    source: hosted
    version: "1.0.0"
''',
            sources,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Content-hash has incorrect length'),
            ),
          ),
        );
      });

      test('ignores extra stuff in file', () {
        LockFile.parse(
          '''
extra:
  some: stuff
packages:
  foo:
    bonus: not used
    version: 1.2.3
    source: fake
    description: foo desc
''',
          sources,
        );
      });
    });

    test('serialize() dumps the lockfile to YAML', () {
      var lockfile = LockFile(
        [
          PackageId(
            'foo',
            Version.parse('1.2.3'),
            ResolvedHostedDescription(
              HostedDescription('foo', 'https://foo.com'),
              sha256: null,
            ),
          ),
          PackageId(
            'bar',
            Version.parse('3.2.1'),
            ResolvedHostedDescription(
              HostedDescription('bar', 'https://bar.com'),
              sha256: null,
            ),
          ),
        ],
        devDependencies: {'bar'},
      );

      expect(
        loadYaml(lockfile.serialize('', cache)),
        equals({
          'sdks': {'dart': 'any'},
          'packages': {
            'foo': {
              'version': '1.2.3',
              'source': 'hosted',
              'description': {'name': 'foo', 'url': 'https://foo.com'},
              'dependency': 'transitive'
            },
            'bar': {
              'version': '3.2.1',
              'source': 'hosted',
              'description': {'name': 'bar', 'url': 'https://bar.com'},
              'dependency': 'direct dev'
            }
          }
        }),
      );
    });
  });
}
