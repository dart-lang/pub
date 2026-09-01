// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/path.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../golden_file.dart';
import '../../package_server.dart';
import '../../test_pub.dart';

Future<void> main() async {
  testWithGolden('no advisories to show', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.0.0']),
        AffectedPackage(name: 'foo', ecosystem: 'NotPub', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden(
    'no advisories to show - a single advisory with no pub packages',
    (ctx) async {
      final server = await servePackages();
      server
        ..serve('foo', '1.0.0')
        ..serve('foo', '1.2.3')
        ..serve('baz', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'app',
          'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
        }),
      ]).create();

      server.addAdvisory(
        advisoryId: '123',
        displayUrl: 'https://github.com/advisories/123',
        affectedPackages: [
          AffectedPackage(
            name: 'foo',
            ecosystem: 'NotPub',
            versions: ['1.2.3'],
          ),
        ],
      );
      await ctx.run(['get']);
    },
  );

  testWithGolden('several advisories, one of which has no pub packages', (
    ctx,
  ) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', ecosystem: 'NotPub', versions: ['1.2.3']),
      ],
    );

    server.addAdvisory(
      advisoryId: '456',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('show advisory', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('show advisories', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    server.addAdvisory(
      advisoryId: '456',
      displayUrl: 'https://github.com/advisories/456',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('show max 5 advisories', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '000',
      displayUrl: 'https://github.com/advisories/000',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '111',
      displayUrl: 'https://github.com/advisories/111',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '222',
      displayUrl: 'https://github.com/advisories/222',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '333',
      displayUrl: 'https://github.com/advisories/333',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '444',
      displayUrl: 'https://github.com/advisories/444',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '555',
      displayUrl: 'https://github.com/advisories/555',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '666',
      displayUrl: 'https://github.com/advisories/666',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('show advisory - newer version available', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.0.0')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();
    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('show advisory - same package mentioned twice', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.0.0']),
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    await ctx.run(['get']);
  });

  testWithGolden('no advisory available from pub.dev', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('no_advisory_pkg', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'no_advisory_pkg': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'no_advisory_pkg', versions: ['1.0.0']),
        AffectedPackage(name: 'foo', versions: ['1.0.0']),
      ],
    );

    server.handle(
      '/api/packages/no_advisory_pkg/advisories',
      (request) => Response.notFound(null),
    );

    await ctx.run(
      ['get'],
      environment: {'_PUB_TEST_DEFAULT_HOSTED_URL': globalServer.url},
    );
  });

  testWithGolden('no advisory available', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('no_advisory_pkg', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'no_advisory_pkg': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'no_advisory_pkg', versions: ['1.0.0']),
        AffectedPackage(name: 'foo', versions: ['1.0.0']),
      ],
    );

    server.handle(
      '/api/packages/no_advisory_pkg/advisories',
      (request) => Response.notFound(null),
    );

    await ctx.run(['get']);
  });

  testWithGolden('show id if no display url is present', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: 'ABCD-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    server.addAdvisory(
      advisoryId: 'VXYZ-1234-5678-9101',
      displayUrl: 'https://github.com/advisories/VXYZ-1234-5678-9101',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('do not show ignored advisories', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.0.0')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
        'ignored_advisories': ['123'],
      }),
    ]).create();
    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '456',
      displayUrl: 'https://github.com/advisories/456',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('do not show ignored advisories - aliases', (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.2.3')
      ..serve('foo', '2.0.0')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'baz': '^1.0.0'},
        'ignored_advisories': ['abc'],
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      aliases: ['abc', 'def'],
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );
    server.addAdvisory(
      advisoryId: '456',
      displayUrl: 'https://github.com/advisories/456',
      aliases: ['cde'],
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    await ctx.run(['get']);
  });

  testWithGolden('malformed advisories response', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    server.handle(
      '/api/packages/foo/advisories',
      (request) => Response.ok('{"advisories": "not a list"}'),
    );

    await ctx.run(['get']);
  });

  test('do not fetch advisories when.`--offline`', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      aliases: ['abc', 'def'],
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    await pubGet();
    server.serveErrors(); // Ensures that the server gets no requests

    File(
      p.join(d.sandbox, d.hostedCachePath(), '.cache', 'foo-advisories.json'),
    ).deleteSync();
    File(p.join(d.sandbox, appPath, 'pubspec.lock')).deleteSync();
    await pubGet(args: ['--offline']);
  });

  test('subsequent pub get reads advisories and status from cache on a new '
      'resolution without network calls for advisories', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.2.3']),
      ],
    );

    // First fetch: populates the cache
    await pubGet(output: contains('affected by advisory'));

    // Mock both endpoints to return 500 Internal Server Error.
    // If the client tries to hit the network for status or advisories,
    // it will fail and not report the advisory.
    server.handle(
      '/api/packages/foo/advisories',
      (request) => Response.internalServerError(),
    );
    server.handle(
      '/api/packages/foo',
      (request) => Response.internalServerError(),
    );

    // Second fetch: the resolution is up to date, and therefore reused.
    // It should read advisories from disk cache and print
    // the advisory warning, making zero network requests.
    await pubGet(output: contains('affected by advisory'));
  });

  test('sanitizes escape sequences in displayUrl and id', () async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {'foo': '^1.0.0', 'bar': '^1.0.0'},
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: 'ID-1\x1b]52;c;evil\x07',
      displayUrl: 'https://example.com/advisory/\x1b]52;c;evil\x07',
      affectedPackages: [
        AffectedPackage(name: 'foo', versions: ['1.0.0']),
      ],
    );
    server.addAdvisory(
      advisoryId: 'ID-2\x1b]52;c;evil\x07',
      affectedPackages: [
        AffectedPackage(name: 'bar', versions: ['1.0.0']),
      ],
    );

    await pubGet(
      output: allOf(
        contains('https://example.com/advisory/ ]52;c;evil '),
        contains('ID-2 ]52;c;evil '),
      ),
    );
  });
}
