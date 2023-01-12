// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('chooses best version matching override constraint', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('foo', '3.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>2.0.0'},
          'dependency_overrides': {'foo': '<3.0.0'}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
      ]).validate();
    });

    test('treats override as implicit dependency', () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependency_overrides': {'foo': 'any'}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      ]).validate();
    });

    test('ignores other constraints on overridden package', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('foo', '3.0.0')
        ..serve(
          'bar',
          '1.0.0',
          pubspec: {
            'dependencies': {'foo': '5.0.0-nonexistent'}
          },
        );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'bar': 'any'},
          'dependency_overrides': {'foo': '<3.0.0'}
        })
      ]).create();

      await pubCommand(command);

      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '2.0.0'),
        d.packageConfigEntry(name: 'bar', version: '1.0.0'),
      ]).validate();
    });

    test('ignores SDK constraints', () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '5.6.7-fblthp'}
        },
      );

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependency_overrides': {'foo': 'any'}
        })
      ]).create();

      await pubCommand(command);
      await d.appPackageConfigFile([
        d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      ]).validate();
    });

    test('informs about overridden dependencies', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('bar', '1.0.0');

      await d
          .dir('baz', [d.libDir('baz'), d.libPubspec('baz', '0.0.1')]).create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependency_overrides': {
            'foo': 'any',
            'bar': 'any',
            'baz': {'path': '../baz'}
          }
        })
      ]).create();

      var bazPath = path.join('..', 'baz');

      await runPub(
        args: [command.name],
        output: contains('''
! bar 1.0.0 (overridden)
! baz 0.0.1 from path $bazPath (overridden)
! foo 1.0.0 (overridden)
'''),
      );
    });
  });
}
