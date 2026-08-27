// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub sends If-None-Match and handles 304 Not Modified for cached '
      'package listings', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    // First run fetches from server and caches listing with ETag.
    await pubGet();

    final cachePath = p.join(
      d.sandbox,
      'cache',
      'hosted',
      'localhost%58${server.port}',
      '.cache',
      'foo-versions.json',
    );
    expect(File(cachePath).existsSync(), isTrue);
    final cacheContent = File(cachePath).readAsStringSync();
    expect(cacheContent, contains('_etag'));

    // Second run with pub upgrade sends If-None-Match.
    // The server will return 304 Not Modified and pub will resolve
    // successfully.
    await pubUpgrade();

    final lockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(lockFile, contains('version: "1.0.0"'));

    // Now serve a new version of foo. The server ETag changes.
    server.serve('foo', '1.1.0');

    // Running pub upgrade should get a 200 OK with the new version.
    await pubUpgrade();

    final updatedLockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(updatedLockFile, contains('version: "1.1.0"'));
  });
}
