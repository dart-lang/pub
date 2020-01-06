// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('gets a package from a pub server', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
  });

  test('URL encodes the package name', () async {
    await serveNoPackages();

    await d.appDir({'bad name!': '1.2.3'}).create();

    await pubGet(
        error: allOf([
          contains(
              "Because myapp depends on bad name! any which doesn't exist (could "
              'not find package bad name! at http://localhost:'),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.UNAVAILABLE);
  });

  test('gets a package from a non-default pub server', () async {
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

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
  });

  group('categorizes dependency types in the lockfile', () {
    setUp(() => servePackages((builder) {
          builder.serve('foo', '1.2.3', deps: {'bar': 'any'});
          builder.serve('bar', '1.2.3');
          builder.serve('baz', '1.2.3', deps: {'qux': 'any'});
          builder.serve('qux', '1.2.3');
          builder.serve('zip', '1.2.3', deps: {'zap': 'any'});
          builder.serve('zap', '1.2.3');
        }));

    test('for main, dev, and overridden dependencies', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': 'any'},
          'dev_dependencies': {'baz': 'any'},
          'dependency_overrides': {'zip': 'any'}
        })
      ]).create();

      await pubGet();

      var packages = loadYaml(
          readTextFile(p.join(d.sandbox, appPath, 'pubspec.lock')))['packages'];
      expect(packages,
          containsPair('foo', containsPair('dependency', 'direct main')));
      expect(packages,
          containsPair('bar', containsPair('dependency', 'transitive')));
      expect(packages,
          containsPair('baz', containsPair('dependency', 'direct dev')));
      expect(packages,
          containsPair('qux', containsPair('dependency', 'transitive')));
      expect(packages,
          containsPair('zip', containsPair('dependency', 'direct overridden')));
      expect(packages,
          containsPair('zap', containsPair('dependency', 'transitive')));
    });

    test('for overridden main and dev dependencies', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': 'any'},
          'dev_dependencies': {'baz': 'any'},
          'dependency_overrides': {'foo': 'any', 'baz': 'any'}
        })
      ]).create();

      await pubGet();

      var packages = loadYaml(
          readTextFile(p.join(d.sandbox, appPath, 'pubspec.lock')))['packages'];
      expect(packages,
          containsPair('foo', containsPair('dependency', 'direct main')));
      expect(packages,
          containsPair('bar', containsPair('dependency', 'transitive')));
      expect(packages,
          containsPair('baz', containsPair('dependency', 'direct dev')));
      expect(packages,
          containsPair('qux', containsPair('dependency', 'transitive')));
    });
  });
}
