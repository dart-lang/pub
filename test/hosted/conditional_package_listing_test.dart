// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
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

  test('pub discards corrupted cached listing before sending If-None-Match and '
      'refetches', () async {
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

    // When the cached listing is corrupted on disk, pub discards it before
    // sending If-None-Match and fetches a fresh listing from the server.
    await pubUpgrade();

    final lockFile =
        File(p.join(d.sandbox, appPath, 'pubspec.lock')).readAsStringSync();
    expect(lockFile, contains('version: "1.0.0"'));
  });

  test(
    'pub fails cleanly without recursing if a broken server responds 304 Not '
    'Modified to an unconditional request',
    () async {
      final server = await servePackages();
      var requestCount = 0;
      server.handle(RegExp(r'/api/packages/foo$'), (request) {
        requestCount++;
        return shelf.Response.notModified();
      });

      await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
      await pubGet(
        error: contains('304 Not Modified trying to find package foo'),
        exitCode: exit_codes.UNAVAILABLE,
      );
      expect(requestCount, 1);
    },
  );

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

  test('pub get revalidates expired cached listing with If-None-Match and '
      'refreshes _fetchedAt on 304 Not Modified', () async {
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

    // Make the cached listing older than the 3-day maxAge.
    final staleTime = DateTime.now().toUtc().subtract(const Duration(days: 5));
    final cached =
        jsonDecode(File(cachePath).readAsStringSync()) as Map<String, dynamic>;
    cached['_fetchedAt'] = staleTime.toIso8601String();
    File(cachePath).writeAsStringSync(jsonEncode(cached));

    var conditionalRequests = 0;
    server.handle(RegExp(r'/api/packages/foo$'), (request) {
      if (request.headers['if-none-match'] == cached['_etag']) {
        conditionalRequests++;
        return shelf.Response.notModified(
          headers: {'etag': cached['_etag'] as String},
        );
      }
      return shelf.Response.badRequest(body: 'Expected If-None-Match');
    });

    // Running pub get with an existing lockfile checks package status/hashes.
    // Because the cache is >3 days old, it revalidates with If-None-Match
    // and receives 304 Not Modified.
    server.requestedPaths.clear();
    await pubGet();
    expect(conditionalRequests, 1);
    expect(
      server.requestedPaths.where((p) => p == 'api/packages/foo'),
      hasLength(1),
    );

    // The cached listing's _fetchedAt timestamp on disk should be refreshed,
    // while preserving _etag and versions.
    final refreshed =
        jsonDecode(File(cachePath).readAsStringSync()) as Map<String, dynamic>;
    final refreshedTime = DateTime.parse(refreshed['_fetchedAt'] as String);
    expect(refreshedTime.isAfter(staleTime), isTrue);
    expect(refreshed['_etag'], cached['_etag']);
    expect(refreshed['versions'], cached['versions']);

    // A subsequent pub get sees the refreshed timestamp (<3 days old) and
    // does not contact the server again.
    server.requestedPaths.clear();
    await pubGet();
    expect(
      server.requestedPaths.where((p) => p == 'api/packages/foo'),
      isEmpty,
    );

    // A subsequent pub upgrade when the cached listing is still fresh (<1 day
    // old) sends If-None-Match and handles 304 without rewriting the cache file
    // on disk.
    await pubUpgrade();
    expect(conditionalRequests, 2);
    final afterUpgrade =
        jsonDecode(File(cachePath).readAsStringSync()) as Map<String, dynamic>;
    expect(afterUpgrade['_fetchedAt'], refreshed['_fetchedAt']);
  });
}
