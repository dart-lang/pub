// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from a non-default pub server', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    final server = await startPackageServer();
    server.serve('foo', '0.2.5');
    server.serve('foo', '1.1.0');
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {}).create();

    final url = server.url;

    await pubAdd(args: ['foo:1.2.3', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
    ]).validate();

    await d.appDir(
      dependencies: {
        'foo': {
          'version': '1.2.3',
          'hosted': {'name': 'foo', 'url': url}
        }
      },
    ).validate();
  });

  test('adds multiple packages from a non-default pub server', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    final server = await startPackageServer();
    server.serve('foo', '1.1.0');
    server.serve('foo', '1.2.3');
    server.serve('bar', '0.2.5');
    server.serve('bar', '3.2.3');
    server.serve('baz', '0.1.3');
    server.serve('baz', '1.3.5');

    await d.appDir(dependencies: {}).create();

    final url = server.url;

    await pubAdd(
      args: ['foo:1.2.3', 'bar:3.2.3', 'baz:1.3.5', '--hosted-url', url],
    );

    await d.cacheDir(
      {'foo': '1.2.3', 'bar': '3.2.3', 'baz': '1.3.5'},
      port: server.port,
    ).validate();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
      d.packageConfigEntry(name: 'bar', version: '3.2.3', server: server),
      d.packageConfigEntry(name: 'baz', version: '1.3.5', server: server),
    ]).validate();

    await d.appDir(
      dependencies: {
        'foo': {
          'version': '1.2.3',
          'hosted': {'name': 'foo', 'url': url}
        },
        'bar': {
          'version': '3.2.3',
          'hosted': {'name': 'bar', 'url': url}
        },
        'baz': {
          'version': '1.3.5',
          'hosted': {'name': 'baz', 'url': url}
        }
      },
    ).validate();
  });

  test('fails when adding from an invalid url', () async {
    ensureGit();

    await d.appDir(dependencies: {}).create();

    await pubAdd(
      args: ['foo', '--hosted-url', 'https://invalid-url.foo'],
      error: contains('Got socket error trying to find package foo at '
          'https://invalid-url.foo.'),
      exitCode: exit_codes.DATA,
      environment: {
        // Limit the retries - the url will never go valid.
        'PUB_MAX_HTTP_RETRIES': '1',
      },
    );

    await d.appDir(dependencies: {}).validate();
    await d.dir(appPath, [
      d.nothing('.dart_tool/package_config.json'),
      d.nothing('pubspec.lock'),
      d.nothing('.packages'),
    ]).validate();
  });

  test(
      'adds a package from a non-default pub server with no version constraint',
      () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    final server = await startPackageServer();
    server.serve('foo', '0.2.5');
    server.serve('foo', '1.1.0');
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {}).create();

    final url = server.url;

    await pubAdd(args: ['foo', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
    ]).validate();
    await d.appDir(
      dependencies: {
        'foo': {
          'version': '^1.2.3',
          'hosted': {'name': 'foo', 'url': url}
        }
      },
    ).validate();
  });

  test('adds a package from a non-default pub server with a version constraint',
      () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    final server = await startPackageServer();
    server.serve('foo', '0.2.5');
    server.serve('foo', '1.1.0');
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {}).create();

    final url = server.url;

    await pubAdd(args: ['foo', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
    ]).validate();
    await d.appDir(
      dependencies: {
        'foo': {
          'version': '^1.2.3',
          'hosted': {'name': 'foo', 'url': url}
        }
      },
    ).validate();
  });

  test(
      'adds a package from a non-default pub server with the "any" version '
      'constraint', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    (await servePackages()).serveErrors();

    final server = await startPackageServer();
    server.serve('foo', '0.2.5');
    server.serve('foo', '1.1.0');
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {}).create();

    final url = server.url;

    await pubAdd(args: ['foo:any', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3', server: server),
    ]).validate();
    await d.appDir(
      dependencies: {
        'foo': {
          'version': 'any',
          'hosted': {'name': 'foo', 'url': url}
        }
      },
    ).validate();
  });
}
