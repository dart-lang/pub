// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  group('pub upgrade --tighten', () {
    test('updates dependency constraints lower bounds and shows summary report',
        () async {
      final server = await servePackages();

      server.serve('foo', '1.0.0');
      server.serve('bar', '0.2.0');
      server.serve('baz', '0.2.0');
      server.serve('boo', '1.0.0');

      await d.dir('boom', [d.libPubspec('boom', '1.0.0')]).create();
      await d.dir('boom2', [d.libPubspec('boom2', '1.5.0')]).create();

      await d.appDir(
        dependencies: {
          'foo': '^1.0.0',
          'bar': '>=0.1.2 <3.0.0',
          'baz': '0.2.0',
          'boo': 'any',
          'boom': {'path': '../boom'},
          'boom2': {'path': '../boom2', 'version': '^1.0.0'},
        },
      ).create();

      await pubGet();

      server.serve('foo', '1.5.0');
      server.serve('bar', '1.5.0');

      await pubUpgrade(
        args: ['--tighten', '--dry-run'],
        output: allOf([
          contains('Would change 4 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^1.5.0'),
          contains('bar: >=0.1.2 <3.0.0 -> >=1.5.0 <3.0.0'),
          contains('boo: any -> ^1.0.0'),
          contains('boom2: ^1.0.0 -> ^1.5.0'),
        ]),
      );

      await pubUpgrade(
        args: ['--tighten'],
        output: allOf([
          contains('Changed 4 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^1.5.0'),
          contains('bar: >=0.1.2 <3.0.0 -> >=1.5.0 <3.0.0'),
          contains('boo: any -> ^1.0.0'),
          contains('boom2: ^1.0.0 -> ^1.5.0'),
        ]),
      );

      await d.appDir(
        dependencies: {
          'foo': '^1.5.0',
          'bar': '>=1.5.0 <3.0.0',
          'baz': '0.2.0',
          'boo': '^1.0.0',
          'boom': {'path': '../boom'},
          'boom2': {'path': '../boom2', 'version': '^1.5.0'},
        },
      ).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.5.0'),
        d.packageConfigEntry(name: 'bar', version: '1.5.0'),
        d.packageConfigEntry(name: 'baz', version: '0.2.0'),
        d.packageConfigEntry(name: 'boo', version: '1.0.0'),
        d.packageConfigEntry(name: 'boom', path: '../boom'),
        d.packageConfigEntry(name: 'boom2', path: '../boom2'),
      ]).validate();
    });

    test(
        '--major-versions updates dependency constraints lower bounds and shows summary report',
        () async {
      final server = await servePackages();

      server.serve('foo', '1.0.0');
      server.serve('bar', '1.0.0');

      await d.appDir(
        dependencies: {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      ).create();

      await pubGet();

      server.serve('foo', '2.0.0');
      server.serve('bar', '1.5.0');

      await pubUpgrade(
        args: ['--tighten', '--major-versions'],
        output: allOf([
          contains('Changed 2 constraints in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^2.0.0'),
          contains('bar: ^1.0.0 -> ^1.5.0'),
        ]),
      );

      await d.appDir(
        dependencies: {
          'foo': '^2.0.0',
          'bar': '^1.5.0',
        },
      ).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
        d.packageConfigEntry(name: 'bar', version: '1.5.0'),
      ]).validate();
    });

    test('can tighten a specific package', () async {
      final server = await servePackages();

      server.serve('foo', '1.0.0');
      server.serve('bar', '1.0.0');

      await d.appDir(
        dependencies: {
          'foo': '^1.0.0',
          'bar': '^1.0.0',
        },
      ).create();

      await pubGet();

      server.serve('foo', '1.5.0');
      server.serve('bar', '1.5.0');

      await pubUpgrade(
        args: ['--tighten', 'foo'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('foo: ^1.0.0 -> ^1.5.0'),
        ]),
      );

      await d.appDir(
        dependencies: {
          'foo': '^1.5.0',
          'bar': '^1.0.0',
        },
      ).validate();
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.5.0'),
        d.packageConfigEntry(name: 'bar', version: '1.0.0'),
      ]).validate();

      server.serve('foo', '2.0.0');
      server.serve('bar', '2.0.0');

      await pubUpgrade(
        args: ['--tighten', 'bar', '--major-versions'],
        output: allOf([
          contains('Changed 1 constraint in pubspec.yaml:'),
          contains('bar: ^1.0.0 -> ^2.0.0'),
        ]),
      );
    });
  });
}
