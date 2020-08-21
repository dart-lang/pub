// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('removes a package from dependencies', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackagesFile({}).validate();
    await d.appDir({}).validate();
  });

  test('dry-run does not actually remove dependency', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();

    await pubRemove(
        args: ['foo', '--dry-run'],
        output: allOf([
          contains('These packages are no longer being depended on:'),
          contains('- foo 1.2.3')
        ]));

    await d.appDir({'foo': '1.2.3'}).validate();
  });

  test('prints a warning if package does not exist', () async {
    await d.appDir().create();
    await pubRemove(
        args: ['foo'],
        warning: contains('Package "foo" was not found in pubspec.yaml!'));

    await d.appDir().validate();
  });

  test('prints a warning if the dependencies map does not exist', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'})
    ]).create();
    await pubRemove(
        args: ['foo'],
        warning: contains('Package "foo" was not found in pubspec.yaml!'));

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'})
    ]).validate();
  });

  test('removes a package from dev_dependencies', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.2.3'}
      })
    ]).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackagesFile({}).validate();

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
    ]).validate();
  });

  test('removes multiple packages from dependencies and dev_dependencies',
      () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.3');
      builder.serve('bar', '2.3.4');
      builder.serve('baz', '3.2.1');
      builder.serve('jfj', '0.2.1');
    });

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
    await d.appPackagesFile({'jfj': '0.2.1'}).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'jfj': '0.2.1'},
        'dev_dependencies': {}
      })
    ]).validate();
  });

  test('removes git dependencies', () async {
    ensureGit();
    final repo = d.git('foo.git', [
      d.dir('subdir', [d.libPubspec('foo', '1.0.0'), d.libDir('foo', '1.0.0')])
    ]);
    await repo.create();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'path': 'subdir'}
      }
    }).create();

    await pubGet();

    await pubRemove(args: ['foo']);
    await d.appPackagesFile({}).validate();
    await d.appDir({}).validate();
  });

  test('removes path dependencies', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.appDir({
      'foo': {'path': '../foo'}
    }).create();

    await pubGet();

    await pubRemove(args: ['foo']);
    await d.appPackagesFile({}).validate();
    await d.appDir({}).validate();
  });

  test('removes hosted dependencies', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({
      'foo': {
        'version': '1.2.3',
        'hosted': {'name': 'foo', 'url': 'http://localhost:${server.port}'}
      }
    }).create();

    await pubGet();

    await pubRemove(args: ['foo']);
    await d.appPackagesFile({}).validate();
    await d.appDir({}).validate();
  });
}
