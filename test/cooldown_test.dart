// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/source/root.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('policies field requires language version 3.15', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp_gating',
        'environment': {'sdk': '^3.14.0'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains(
        'The "policies" field requires at least language version 3.15',
      ),
      exitCode: 65,
    );
  });

  test('policies field does not allow unknown fields', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp_gating',
        'environment': {'sdk': '^3.15.0'},
        'policies': {'unknown_field': 'value'},
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains(
        'Invalid policies field "unknown_field". Only "cooldown" is supported.',
      ),
      exitCode: 65,
    );
  });

  test('cooldown policy prevents resolving new versions', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});
  });

  test('cooldown policy respects exclusions', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {
            'min_age': '7d',
            'exclude': {'foo': 'any'},
          },
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.1'});
  });

  test('strict policy treats missing publication date as violation', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve('foo', '1.0.1'); // Missing date

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});
  });

  test('fails when publication date does not contain timezone', () async {
    final server = await servePackages();
    server.handle(
      RegExp(r'/api/packages/foo'),
      (request) => shelf.Response.ok(
        jsonEncode({
          'name': 'foo',
          'uploaders': ['nweiz@google.com'],
          'versions': [
            {
              'pubspec': {
                'name': 'foo',
                'version': '1.0.0',
                'environment': {'sdk': '^3.0.0'},
              },
              'version': '1.0.0',
              'archive_url': '${server.url}/packages/foo/versions/1.0.0.tar.gz',
              'published': '2026-05-28T09:09:29', // Missing timezone!
            },
          ],
        }),
        headers: {'content-type': 'application/vnd.pub.v2+json'},
      ),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: allOf(
        contains('version solving failed'),
        contains('Got badly formatted response trying to find package foo'),
      ),
      exitCode: 65,
    );
  });

  test('strict policy allows missing publication date if excluded', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve('foo', '1.0.1'); // Missing date

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {
            'min_age': '7d',
            'exclude': {'foo': 'any'},
          },
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.1'});
  });

  test('nice error message when no matching versions old enough', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(
      error: allOf(
        contains('version solving failed'),
        contains('all versions of foo are too new'),
        contains('The cooldown policy is defined at'),
        contains('pubspec.yaml'),
        contains('Consider excluding "foo" from the cooldown policy'),
      ),
    );
  });

  test('nice error message when one version is too new and '
      'other is blocked by constraint', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );
    server.serve(
      'bar',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
      pubspec: {
        'dependencies': {'foo': '>1.0.0'},
      },
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any', 'bar': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(
      error: allOf(
        contains('version solving failed'),
        contains('version 1.0.1 of foo is too new'),
        contains('depends on foo >1.0.0'),
      ),
    );
  });

  test('pub outdated shows cooldown blocked versions', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    // Run pub get first to create lockfile
    await expectResolves(result: {'foo': '1.0.0'});

    await runPub(
      args: ['outdated'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      output: allOf([
        contains('foo'),
        contains('1.0.0'), // Current
        contains('1.0.0'), // Upgradable
        contains('1.0.0'), // Resolvable
        contains('1.0.1'), // Latest
        contains('Version 1.0.1 is too new for the cooldown policy.'),
      ]),
    );
  });

  test('pub get report shows cooldown blocked versions', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': '^1.0.0'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      output: allOf([
        contains('foo 1.0.0'),
        contains('(1.0.1 available (blocked by cooldown))'),
      ]),
    );
  });
  test(
    'stability: true blocks version if newer release within window',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        published: DateTime.now().subtract(const Duration(days: 10)),
      );
      server.serve(
        'foo',
        '1.0.1',
        published: DateTime.now().subtract(
          const Duration(days: 8),
        ), // Released 2 days after 1.0.0!
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '^3.15.0'},
          'dependencies': {'foo': '1.0.0'},
          'policies': {
            'cooldown': {'min_age': '7d', 'stability': true},
          },
        }),
      ]).create();

      await expectResolves(
        error: contains(
          'version 1.0.0 of foo is unstable (newer release within 7 days)',
        ),
      );
    },
  );

  test('stability: true allows version if old enough and no '
      'newer release within window', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(
        const Duration(days: 2),
      ), // Released 8 days after 1.0.0!
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': '1.0.0'},
        'policies': {
          'cooldown': {'min_age': '7d', 'stability': true},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});
  });

  test('stability: true does not block version if newer release '
      'was published before this version', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 20)),
    );
    // A newer version 2.0.0 is published.
    server.serve(
      'foo',
      '2.0.0',
      published: DateTime.now().subtract(const Duration(days: 15)),
    );
    // A patch/backport version 1.0.1 is published *after* 2.0.0
    // (e.g. 10 days ago).
    // 1.0.1 is older than 7 days (min_age), and 2.0.0 was published
    // *before* 1.0.1, so stability shouldn't block 1.0.1.
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': '1.0.1'},
        'policies': {
          'cooldown': {'min_age': '7d', 'stability': true},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.1'});
  });

  test('cooldown policy does not apply to non-hosted packages '
      '(e.g. path dependencies)', () async {
    await d.dir('foo', [
      d.pubspec({'name': 'foo', 'version': '1.0.0'}),
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {
          'foo': {'path': '../foo'},
        },
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves();
  });

  test(
    'before policy restricts newer versions but allows older ones',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        published: DateTime.parse('2026-05-27T12:00:00Z'),
      );
      server.serve(
        'foo',
        '1.0.1',
        published: DateTime.parse('2026-05-28T13:00:00Z'),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '^3.15.0'},
          'dependencies': {'foo': 'any'},
          'policies': {
            'cooldown': {'before': '2026-05-28T12:00:00Z'},
          },
        }),
      ]).create();

      await expectResolves(result: {'foo': '1.0.0'});
    },
  );

  test('fails when both min_age and before are specified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'min_age': '7d', 'before': '2026-05-28T12:00:00Z'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('Only one of "min_age" and "before" can be specified.'),
      exitCode: 65,
    );
  });

  test('fails when neither min_age nor before are specified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {
            'exclude': {'foo': 'any'},
          },
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('One of "min_age" or "before" must be specified.'),
      exitCode: 65,
    );
  });

  test('fails when before lacks UTC indicator Z', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'before': '2026-05-28T12:00:00'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('"before" must be a UTC timestamp in ISO 8601 format'),
      exitCode: 65,
    );
  });

  test('fails when before uses non-UTC timezone offset', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'before': '2026-05-28T12:00:00+02:00'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('"before" must be a UTC timestamp in ISO 8601 format'),
      exitCode: 65,
    );
  });

  test('fails when before is not a valid date string', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'before': 'not-a-date'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('"before" must be a UTC timestamp in ISO 8601 format'),
      exitCode: 65,
    );
  });

  test('fails when stability is used with before', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'before': '2026-05-28T12:00:00Z', 'stability': true},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains(
        '"stability" is only supported when "min_age" is specified.',
      ),
      exitCode: 65,
    );
  });

  test('fails when stability: false is used with before', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'before': '2026-05-28T12:00:00Z', 'stability': false},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains(
        '"stability" is only supported when "min_age" is specified.',
      ),
      exitCode: 65,
    );
  });

  test('exclude policy supports version-specific constraints', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );
    server.serve(
      'foo',
      '2.0.0',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {
            'min_age': '7d',
            'exclude': {'foo': '^1.0.0'},
          },
        },
      }),
    ]).create();

    // 1.0.1 matches ^1.0.0 and is allowed despite cooldown.
    // 2.0.0 is in cooldown and does not match ^1.0.0, so it is blocked.
    await expectResolves(result: {'foo': '1.0.1'});
  });

  test('fails when exclude is not a map', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {
            'min_age': '7d',
            'exclude': ['foo'], // List instead of Map
          },
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('"exclude" must be a map'),
      exitCode: 65,
    );
  });

  test('fails when exclude map has invalid package name', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {
            'min_age': '7d',
            'exclude': {'not a valid name!': 'any'},
          },
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('Not a valid package name.'),
      exitCode: 65,
    );
  });

  test('fails on unknown field inside cooldown', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'policies': {
          'cooldown': {'min_age': '7d', 'min-age': '3d'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('Invalid cooldown field "min-age".'),
      exitCode: 65,
    );
  });

  test('fails on non-string keys inside policies and cooldown', () async {
    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
environment:
  sdk: ^3.15.0
policies:
  123: value
'''),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('Invalid policies field "123".'),
      exitCode: 65,
    );

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
environment:
  sdk: ^3.15.0
policies:
  cooldown:
    min_age: 7d
    123: value
'''),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains('Invalid cooldown field "123".'),
      exitCode: 65,
    );
  });

  test('allows empty exclude field in cooldown policy', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
environment:
  sdk: ^3.15.0
dependencies:
  foo: any
policies:
  cooldown:
    min_age: 7d
    exclude:
'''),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});
  });

  test('cooldown policy in non-root workspace member applies to get, report, '
      'and outdated', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'root_app',
        'environment': {'sdk': '^3.15.0'},
        'workspace': ['pkgs/member'],
      }),
      d.dir('pkgs', [
        d.dir('member', [
          d.pubspec({
            'name': 'member',
            'environment': {'sdk': '^3.15.0'},
            'resolution': 'workspace',
            'dependencies': {'foo': '^1.0.0'},
            'policies': {
              'cooldown': {'min_age': '7d'},
            },
          }),
        ]),
      ]),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      output: allOf([
        contains('foo 1.0.0'),
        contains('(1.0.1 available (blocked by cooldown))'),
      ]),
    );

    await runPub(
      args: ['outdated'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      output: allOf([
        contains('foo'),
        contains('1.0.0'),
        contains('1.0.1'),
        contains('Version 1.0.1 is too new for the cooldown policy.'),
      ]),
    );
  });

  test('rejects multiple policies definitions in workspace', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'root_app',
        'environment': {'sdk': '^3.15.0'},
        'workspace': ['pkgs/member'],
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
      d.dir('pkgs', [
        d.dir('member', [
          d.pubspec({
            'name': 'member',
            'environment': {'sdk': '^3.15.0'},
            'resolution': 'workspace',
            'policies': {
              'cooldown': {'min_age': '3d'},
            },
          }),
        ]),
      ]),
    ]).create();

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: contains(
        'Only a single policies configuration is allowed across all '
        'workspace pubspec.yaml files.',
      ),
      exitCode: 1,
    );
  });

  test(
    'pub get report and outdated flag latest stable blocked by stability',
    () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        published: DateTime.now().subtract(const Duration(days: 30)),
      );
      server.serve(
        'foo',
        '1.0.1',
        published: DateTime.now().subtract(const Duration(days: 15)),
      );
      // Newer prerelease published 1 day after 1.0.1 breaks 1.0.1's stability.
      server.serve(
        'foo',
        '1.0.2-dev.1',
        published: DateTime.now().subtract(const Duration(days: 14)),
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '^3.15.0'},
          'dependencies': {'foo': '^1.0.0'},
          'policies': {
            'cooldown': {'min_age': '7d', 'stability': true},
          },
        }),
      ]).create();

      await runPub(
        args: ['get'],
        environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
        output: allOf([
          contains('foo 1.0.0'),
          contains('(1.0.1 available (blocked by cooldown))'),
        ]),
      );

      await runPub(
        args: ['outdated'],
        environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
        output: allOf([
          contains('foo'),
          contains('1.0.0'),
          contains('1.0.1'),
          contains(
            'Version 1.0.1 is considered unstable by the cooldown policy.',
          ),
        ]),
      );
    },
  );

  test(
    'reports accurate reason when all versions lack publication date',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0'); // Missing published date
      server.serve('foo', '1.0.1'); // Missing published date

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '^3.15.0'},
          'dependencies': {'foo': 'any'},
          'policies': {
            'cooldown': {'min_age': '7d'},
          },
        }),
      ]).create();

      await expectResolves(
        error: allOf(
          contains('version solving failed'),
          contains(
            'all versions of foo lack publication dates required by the '
            'cooldown policy',
          ),
          contains('Consider excluding "foo" from the cooldown policy'),
        ),
      );
    },
  );

  test('CooldownPolicy.blockReason uses provided reference timestamp', () {
    final now = DateTime.utc(2026, 6, 10, 12);
    final exclude = <String, VersionConstraint>{
      'exempt': VersionConstraint.any,
    };
    final policy = CooldownPolicy.minAge(
      minAge: const Duration(days: 7),
      exclude: exclude,
      stability: true,
    );
    // Mutating the caller-supplied map does not affect the policy.
    exclude['foo'] = VersionConstraint.any;

    final exactBoundary = now.subtract(const Duration(days: 7));
    final oneSecondTooNew = exactBoundary.add(const Duration(seconds: 1));
    final v100 = Version.parse('1.0.0');
    final v101 = Version.parse('1.0.1');

    expect(policy.blockReason('foo', v100, exactBoundary, now: now), isNull);
    expect(
      policy.blockReason('foo', v100, oneSecondTooNew, now: now),
      CooldownBlockReason.tooNew,
    );
    expect(
      policy.blockReason('foo', v100, null, now: now),
      CooldownBlockReason.missingPublishedDate,
    );
    expect(
      policy.blockReason('exempt', v100, oneSecondTooNew, now: now),
      isNull,
    );
    expect(
      policy.blockReason(
        'foo',
        v100,
        now.subtract(const Duration(days: 10)),
        now: now,
        statusMap: {
          v100: PackageStatus(
            published: now.subtract(const Duration(days: 10)),
          ),
          v101: PackageStatus(published: now.subtract(const Duration(days: 8))),
        },
      ),
      CooldownBlockReason.unstable,
    );
  });

  test('fails cleanly with solver explanation when locked package is removed '
      'from server under cooldown policy', () async {
    final server = await servePackages();
    final now = DateTime.now().toUtc();
    server.serve(
      'foo',
      '1.0.0',
      published: now.subtract(const Duration(days: 10)),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '^3.15.0'},
        'dependencies': {'foo': 'any'},
        'policies': {
          'cooldown': {'min_age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});

    // Remove foo from the server so the listing returns 404.
    server.clearPackages();

    // While foo 1.0.0 is still in cache, describe() succeeds from cache,
    // cooldown rejects it due to missing publication date, and the solver
    // reports a structured failure instead of an uncaught exception.
    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: allOf(
        contains('version solving failed'),
        contains("which doesn't exist"),
      ),
      exitCode: exit_codes.UNAVAILABLE,
    );

    // Clear the pub cache so describe() also fails with
    // PackageNotFoundException; the solver still produces a clean
    // explanation rather than letting PackageNotFoundException escape.
    Directory(p.join(d.sandbox, cachePath)).deleteSync(recursive: true);

    await runPub(
      args: ['get'],
      environment: {'_PUB_TEST_SDK_VERSION': '3.15.0'},
      error: allOf(
        contains('version solving failed'),
        contains("Because myapp depends on foo any which doesn't exist"),
      ),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });
}

/// Runs "pub get" and makes assertions about its results.
///
/// If [result] is passed, it's parsed as a pubspec-style dependency map, and
/// this asserts that the resulting lockfile matches those dependencies, and
/// that it contains only packages listed in [result].
///
/// If [error] is passed, this asserts that pub's error output matches the
/// value. It may be a String, a [RegExp], or a [Matcher].
///
/// If [output] is passed, this asserts that the results match. It may be a
/// [String], a [RegExp], or a [Matcher].
///
/// Asserts that version solving looks at exactly [tries] solutions. It defaults
/// to allowing only a single solution.
///
/// If [environment] is passed, it's added to the OS environment when running
/// pub.
///
/// If [downgrade] is `true`, this runs "pub downgrade" instead of "pub get".
Future expectResolves({
  Map? result,
  Object? error,
  Object? output,
  int? tries,
  Map<String, String>? environment,
  bool downgrade = false,
}) async {
  await runPub(
    args: [downgrade ? 'downgrade' : 'get'],
    environment: {'_PUB_TEST_SDK_VERSION': '3.15.0', ...?environment},
    output:
        output ??
        (error == null
            ? anyOf(
              contains('Got dependencies!'),
              matches(RegExp(r'Changed \d+ dependenc(ies|y)!')),
            )
            : null),
    error: error,
    silent: contains('Tried ${tries ?? 1} solutions'),
    exitCode: error == null ? 0 : 1,
  );

  if (result == null) return;

  final cache = SystemCache();
  final registry = cache.sources;
  final lockFile = LockFile.load(
    p.join(d.sandbox, appPath, 'pubspec.lock'),
    registry,
  );
  final resultPubspec = Pubspec.fromMap(
    {'dependencies': result},
    registry,
    containingDescription: ResolvedRootDescription.fromDir('.'),
  );

  final ids = {...lockFile.packages};
  for (var dep in resultPubspec.dependencies.values) {
    expect(ids, contains(dep.name));
    final id = ids.remove(dep.name)!;
    final description = dep.description;
    if (description is HostedDescription &&
        (description.url == SystemCache().hosted.defaultUrl)) {
      // If the dep uses the default hosted source, grab it from the test
      // package server rather than pub.dev.
      dep = cache.hosted
          .refFor(dep.name, url: globalServer.url)
          .withConstraint(dep.constraint);
    }
    expect(dep.allows(id), isTrue, reason: 'Expected $id to match $dep.');
  }

  expect(ids, isEmpty, reason: 'Expected no additional packages.');
}
