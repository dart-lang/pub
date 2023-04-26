// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show File;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('removes a package from dependencies', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackageConfigFile([]).validate();
    await d.appDir().validate();
  });

  test('removing a package from dependencies does not affect dev_dependencies',
      () async {
    await servePackages()
      ..serve('foo', '1.2.3')
      ..serve('foo', '1.2.2')
      ..serve('bar', '2.0.0');

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
name: myapp
dependencies:
  foo: 1.2.3

dev_dependencies:
  bar: 2.0.0

environment:
  sdk: '$defaultSdkConstraint'
''')
    ]).create();

    await pubRemove(args: ['foo']);

    await d.cacheDir({'bar': '2.0.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'bar', version: '2.0.0'),
    ]).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'bar': '2.0.0'}
      })
    ]).validate();
  });

  test('dry-run does not actually remove dependency', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();
    await pubGet();

    await pubRemove(
      args: ['foo', '--dry-run'],
      output: allOf([
        contains('These packages are no longer being depended on:'),
        contains('- foo 1.2.3')
      ]),
    );

    await d.appDir(dependencies: {'foo': '1.2.3'}).validate();
  });

  test('prints a warning if package does not exist', () async {
    await d.appDir().create();
    await pubRemove(
      args: ['foo'],
      warning: contains('Package "foo" was not found in pubspec.yaml!'),
    );

    await d.appDir().validate();
  });

  test('prints a warning if the dependencies map does not exist', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'})
    ]).create();
    await pubRemove(
      args: ['foo'],
      warning: contains('Package "foo" was not found in pubspec.yaml!'),
    );

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'})
    ]).validate();
  });

  test('removes a package from dev_dependencies', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.2.3'}
      })
    ]).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackageConfigFile([]).validate();

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'})
    ]).validate();
  });

  test('removes multiple packages from dependencies and dev_dependencies',
      () async {
    await servePackages()
      ..serve('foo', '1.2.3')
      ..serve('bar', '2.3.4')
      ..serve('baz', '3.2.1')
      ..serve('jfj', '0.2.1');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'bar': '>=2.3.4', 'jfj': '0.2.1'},
        'dev_dependencies': {'foo': '^1.2.3', 'baz': '3.2.1'}
      })
    ]).create();
    await pubGet();

    await pubRemove(args: ['foo', 'bar', 'baz']);

    await d.cacheDir({'jfj': '0.2.1'}).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'jfj', version: '0.2.1'),
    ]).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'jfj': '0.2.1'},
      })
    ]).validate();
  });

  test('removes git dependencies', () async {
    final server = await servePackages();
    server.serve('bar', '1.2.3');

    ensureGit();
    final repo = d.git('foo.git', [
      d.dir('subdir', [d.libPubspec('foo', '1.0.0'), d.libDir('foo', '1.0.0')])
    ]);
    await repo.create();

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../foo.git', 'path': 'subdir'}
        },
        'bar': '1.2.3'
      },
    ).create();

    await pubGet();

    await pubRemove(args: ['foo']);

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'bar', version: '1.2.3'),
    ]).validate();
    await d.appDir(dependencies: {'bar': '1.2.3'}).validate();
  });

  test('removes path dependencies', () async {
    final server = await servePackages();
    server.serve('bar', '1.2.3');
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir(
      dependencies: {
        'foo': {'path': '../foo'},
        'bar': '1.2.3'
      },
    ).create();

    await pubGet();

    await pubRemove(args: ['foo']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'bar', version: '1.2.3'),
    ]).validate();
    await d.appDir(dependencies: {'bar': '1.2.3'}).validate();
  });

  test('removes hosted dependencies', () async {
    final server = await servePackages();
    server.serve('bar', '2.0.1');

    var custom = await startPackageServer();
    custom.serve('foo', '1.2.3');

    await d.appDir(
      dependencies: {
        'foo': {
          'version': '1.2.3',
          'hosted': {'name': 'foo', 'url': 'http://localhost:${custom.port}'}
        },
        'bar': '2.0.1'
      },
    ).create();

    await pubGet();

    await pubRemove(args: ['foo']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'bar', version: '2.0.1'),
    ]).validate();
    await d.appDir(dependencies: {'bar': '2.0.1'}).validate();
  });

  test('removes overrides', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
    server.serve('bar', '1.0.0');
    server.serve('bar', '2.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': '^1.0.0'},
        'dev_dependencies': {'bar': '^2.0.0'},
        'dependency_overrides': {'bar': '1.0.0'}
      })
    ]).create();

    await pubGet();

    // Cannot remove the constraint on bar, would create conflict.
    await pubRemove(
      args: ['override:bar'],
      error: contains('version solving failed.'),
      exitCode: 1,
    );
    await pubRemove(args: ['override:bar', 'foo']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'bar', version: '2.0.0'),
    ]).validate();
  });

  test('preserves comments', () async {
    await servePackages()
      ..serve('bar', '1.0.0')
      ..serve('foo', '1.0.0');

    await d.dir(appPath, [
      d.file('pubspec.yaml', '''
        name: myapp
        dependencies: # comment A
            # comment B
            bar: 1.0.0 
            # comment C
            foo: 1.0.0 # comment D
          # comment E
        environment:
          sdk: '$defaultSdkConstraint'
    '''),
    ]).create();

    await pubGet();

    await pubRemove(args: ['bar']);

    await d.appDir(dependencies: {'foo': '1.0.0'}).validate();
    final fullPath = p.join(d.sandbox, appPath, 'pubspec.yaml');
    expect(File(fullPath).existsSync(), true);
    final contents = File(fullPath).readAsStringSync();
    expect(
      contents,
      allOf([
        contains('# comment A'),
        contains('# comment B'),
        contains('# comment C'),
        contains('# comment D'),
        contains('# comment E')
      ]),
    );
  });
  test('removes dependencies or dev_dependencies key if empty', () async {
    await servePackages()
      ..serve('foo', '1.2.3')
      ..serve('bar', '2.3.4');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'bar': '>=2.3.4'},
        'dev_dependencies': {'foo': '^1.2.3'}
      })
    ]).create();
    await pubGet();

    await pubRemove(args: ['foo', 'bar']);

    await d.appPackageConfigFile([]).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
      })
    ]).validate();
  });
}
