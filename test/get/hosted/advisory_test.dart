// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../golden_file.dart';
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
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '123',
      affectedVersions: ['1.0.0'],
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
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '123',
      affectedVersions: ['1.2.3'],
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

    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '123',
      affectedVersions: ['1.2.3'],
    );
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '456',
      affectedVersions: ['1.2.3'],
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
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '123',
      affectedVersions: ['1.2.3'],
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
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '123',
      affectedVersions: ['1.2.3'],
    );
    server.affectVersionsByAdvisory(
      name: 'foo',
      advisoryId: '456',
      affectedVersions: ['1.2.3'],
    );
    await ctx.run(['get']);
  });
}
