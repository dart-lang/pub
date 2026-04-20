// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/source/root.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {'min-age': '7d'},
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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {
            'min-age': '7d',
            'exclude': ['foo'],
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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {'min-age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(result: {'foo': '1.0.0'});
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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {
            'min-age': '7d',
            'exclude': ['foo'],
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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {'min-age': '7d'},
        },
      }),
    ]).create();

    await expectResolves(
      error: allOf(
        contains('version solving failed'),
        contains('all versions of foo are too new'),
        contains('Cooldown policy defined at'),
        contains('pubspec.yaml'),
        contains('Consider excluding "foo" from the cooldown policy'),
      ),
    );
  });

  test(
    'nice error message when one version is too new and other is blocked by constraint',
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
          'dependencies': {'foo': 'any', 'bar': 'any'},
          'policy': {
            'cooldown': {'min-age': '7d'},
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
    },
  );

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
        'dependencies': {'foo': 'any'},
        'policy': {
          'cooldown': {'min-age': '7d'},
        },
      }),
    ]).create();

    // Run pub get first to create lockfile
    await expectResolves(result: {'foo': '1.0.0'});

    await runPub(
      args: ['outdated'],
      output: allOf([
        contains('foo'),
        contains('1.0.0'), // Current
        contains('1.0.0'), // Upgradable
        contains('1.0.0'), // Resolvable
        contains('1.0.1'), // Latest
        contains('Version 1.0.1 is too new for cooldown policy.'),
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
        'dependencies': {'foo': '^1.0.0'},
        'policy': {
          'cooldown': {'min-age': '7d'},
        },
      }),
    ]).create();

    await runPub(
      args: ['get'],
      output: allOf([
        contains('foo 1.0.0'),
        contains('(1.0.1 available (blocked by cooldown))'),
      ]),
    );
  });
  test('stability: true blocks version if newer release within window', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 8)), // Released 2 days after 1.0.0!
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '1.0.0'},
        'policy': {
          'cooldown': {
            'min-age': '7d',
            'stability': true,
          },
        },
      }),
    ]).create();

    await expectResolves(
      error: contains('version 1.0.0 of foo is unstable (newer release within 7 days)'),
    );
  });

  test('stability: true allows version if old enough and no newer release within window', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      published: DateTime.now().subtract(const Duration(days: 10)),
    );
    server.serve(
      'foo',
      '1.0.1',
      published: DateTime.now().subtract(const Duration(days: 2)), // Released 8 days after 1.0.0!
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '1.0.0'},
        'policy': {
          'cooldown': {
            'min-age': '7d',
            'stability': true,
          },
        },
      }),
    ]).create();

    await expectResolves(
      result: {'foo': '1.0.0'},
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
    environment: environment,
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
