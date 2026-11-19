// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub sends If-None-Match and handles 304 Not Modified for cached '
      'package listings', () async {
    final server = await servePackages(serveEtags: true);
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

  test(
    'pub functions normally with servers that do not support ETags',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
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
      // No _etag should be stored when server does not provide an ETag header.
      expect(cacheContent, isNot(contains('_etag')));

      // Subsequent upgrade works normally with 200 OK.
      server.serve('foo', '1.1.0');
      await pubUpgrade();

      final lockFile =
          File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
      expect(lockFile, contains('version: "1.1.0"'));
    },
  );

  test('pub recovers gracefully if cached listing is corrupted when 304 is '
      'received', () async {
    final server = await servePackages(serveEtags: true);
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
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

    // Corrupt the body of the cached file while preserving an ETag.
    // This simulates a disk corruption occurring after an ETag was stored.
    File(
      cachePath,
    ).writeAsStringSync('{"_etag": "W/\\"invalid\\"", "corrupted": true}');

    // pub upgrade will attempt to validate via ETag, and when it fails to
    // parse the cached response on 304, it deletes the cache and refetches.
    await pubUpgrade();

    final lockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(lockFile, contains('version: "1.0.0"'));
  });

  test(
    'retracting a package version updates ETag and is observed on pub upgrade',
    () async {
      final server = await servePackages(serveEtags: true);
      server.serve('foo', '1.0.0');
      server.serve('foo', '2.0.0');

      await d.appDir(dependencies: {'foo': 'any'}).create();
      await pubGet();

      final lockFileBefore =
          File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
      expect(lockFileBefore, contains('version: "2.0.0"'));

      // Retract 2.0.0 on the server. The server's ETag changes.
      server.retractPackageVersion('foo', '2.0.0');

      // Without manually deleting the cache, pub upgrade observes the
      // retraction because the changed ETag causes the server to return 200 OK
      // with the new listing.
      await pubUpgrade(output: contains('foo 2.0.0 (retracted)'));
    },
  );

  test('offline mode works with cached ETag', () async {
    final server = await servePackages(serveEtags: true);
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet();

    // In offline mode, pub should resolve using the cached listing without
    // contacting server.
    await pubGet(args: ['--offline']);

    final lockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(lockFile, contains('version: "1.0.0"'));
  });

  test('ignores invalid or malicious ETags without crashing', () async {
    final server = await servePackages(serveEtags: true);
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
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

    // Inject an invalid ETag with CRLF into the cache file.
    final cached =
        jsonDecode(File(cachePath).readAsStringSync()) as Map<String, dynamic>;
    cached['_etag'] = 'W/"legit"\r\nX-Injected: attack';
    File(cachePath).writeAsStringSync(jsonEncode(cached));

    // pub upgrade should ignore the invalid ETag, not send it, and not crash.
    await pubUpgrade();

    final lockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(lockFile, contains('version: "1.0.0"'));
  });
}
