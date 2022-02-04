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
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '0.2.5');
      builder.serve('foo', '1.1.0');
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({}).create();

    final url = server.url;

    await pubAdd(args: ['foo:1.2.3', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({
      'foo': {
        'version': '1.2.3',
        'hosted': {'name': 'foo', 'url': url}
      }
    }).validate();
  });

  test('fails when adding from an invalid url', () async {
    ensureGit();

    await d.appDir({}).create();

    await pubAdd(
      args: ['foo', '--hosted-url', 'https://invalid-url.foo'],
      error: contains('Could not resolve URL "https://invalid-url.foo".'),
      exitCode: exit_codes.DATA,
      environment: {
        // Limit the retries - the url will never go valid.
        'PUB_MAX_HTTP_RETRIES': '1',
      },
    );

    await d.appDir({}).validate();
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
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '0.2.5');
      builder.serve('foo', '1.1.0');
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({}).create();

    final url = server.url;

    await pubAdd(args: ['foo', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({
      'foo': {
        'version': '^1.2.3',
        'hosted': {'name': 'foo', 'url': url}
      }
    }).validate();
  });

  test('adds a package from a non-default pub server with a version constraint',
      () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '0.2.5');
      builder.serve('foo', '1.1.0');
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({}).create();

    final url = server.url;

    await pubAdd(args: ['foo', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({
      'foo': {
        'version': '^1.2.3',
        'hosted': {'name': 'foo', 'url': url}
      }
    }).validate();
  });

  test(
      'adds a package from a non-default pub server with the "any" version '
      'constraint', () async {
    // Make the default server serve errors. Only the custom server should
    // be accessed.
    await serveErrors();

    var server = await PackageServer.start((builder) {
      builder.serve('foo', '0.2.5');
      builder.serve('foo', '1.1.0');
      builder.serve('foo', '1.2.3');
    });

    await d.appDir({}).create();

    final url = server.url;

    await pubAdd(args: ['foo:any', '--hosted-url', url]);

    await d.cacheDir({'foo': '1.2.3'}, port: server.port).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({
      'foo': {
        'version': 'any',
        'hosted': {'name': 'foo', 'url': url}
      }
    }).validate();
  });
}
