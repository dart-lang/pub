// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
      }),
    ]).create();

    server.addAdvisory(
      advisoryId: '123',
      displayUrl: 'https://github.com/advisories/123',
      affectedPackages: [
        AffectedPackage(name: 'foo', ecosystem: 'NotPub', versions: ['1.2.3']),
      ],
    );
    await ctx.run(['get']);
  });

  testWithGolden('several advisories, one of which has no pub packages',
      (ctx) async {
    final server = await servePackages();
    server
      ..serve('foo', '1.0.0')
      ..serve('foo', '1.2.3')
      ..serve('baz', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'app',
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'no_advisory_pkg': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'no_advisory_pkg': '^1.0.0',
        },
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
        'dependencies': {
          'foo': '^1.0.0',
          'baz': '^1.0.0',
        },
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
      d.pubspec(
        {
          'name': 'app',
          'dependencies': {
            'foo': '^1.0.0',
            'baz': '^1.0.0',
          },
          'ignored_advisories': ['123'],
        },
      ),
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
      d.pubspec(
        {
          'name': 'app',
          'dependencies': {
            'foo': '^1.0.0',
            'baz': '^1.0.0',
          },
          'ignored_advisories': ['abc'],
        },
      ),
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
}
