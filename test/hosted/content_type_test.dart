// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('gets a package from a server that returns application/json', () async {
    final server = await servePackages();
    server.contentType = 'application/json';
    server.serve('foo', '1.2.3');

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3'}).validate();
  });

  test(
    'gets a package from a server that returns application/json with charset',
    () async {
      final server = await servePackages();
      server.contentType = 'application/json; charset=utf-8';
      server.serve('foo', '1.2.3');

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubGet();

      await d.cacheDir({'foo': '1.2.3'}).validate();
    },
  );

  test(
    'gets multiple versions from a server that returns application/json',
    () async {
      final server = await servePackages();
      server.contentType = 'application/json';
      server.serve('foo', '1.0.0');
      server.serve('foo', '1.2.3');

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubGet();

      await d.cacheDir({'foo': '1.2.3'}).validate();
    },
  );

  test(
    'gets a package with dependencies from a server returning application/json',
    () async {
      final server = await servePackages();
      server.contentType = 'application/json';
      server.serve('foo', '1.0.0', deps: {'bar': '^1.0.0'});
      server.serve('bar', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

      await pubGet();

      await d.cacheDir({'foo': '1.0.0', 'bar': '1.0.0'}).validate();
    },
  );
}
