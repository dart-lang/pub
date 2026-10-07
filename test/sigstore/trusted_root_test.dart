// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub/src/exceptions.dart';
import 'package:pub/src/path.dart';
import 'package:pub/src/sigstore/trusted_root.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;

String _tufRoleJson({required int version, required DateTime expires}) =>
    jsonEncode({
      'signed': {
        'version': version,
        'expires': expires.toUtc().toIso8601String(),
      },
    });

void main() {
  tearDown(() {
    debugTrustedRootRefresher = null;
  });

  test('loads trusted_root.json from explicit override path', () async {
    await d.dir('custom_ca', [
      d.file(
        'trusted_root.json',
        '{"mediaType":"test","certificateAuthorities":[]}',
      ),
    ]).create();

    final customPath = p.join(d.sandbox, 'custom_ca', 'trusted_root.json');
    final root = loadTrustedRoot(overridePath: customPath);

    expect(root!['mediaType'], equals('test'));
    expect(root['certificateAuthorities'], isEmpty);
  });

  test('throws DataException for non-existent override path', () {
    expect(
      () => loadTrustedRoot(overridePath: '/non/existent/path.json'),
      throwsA(isA<DataException>()),
    );
  });

  test('throws DataException for invalid JSON in trusted root file', () async {
    await d.dir('bad_ca', [
      d.file('trusted_root.json', 'invalid json content'),
    ]).create();

    final badPath = p.join(d.sandbox, 'bad_ca', 'trusted_root.json');
    expect(
      () => loadTrustedRoot(overridePath: badPath),
      throwsA(isA<DataException>()),
    );
  });

  test('loads trusted_root.json from pub cache', () async {
    await d.dir('cache', [
      d.dir('sigstore', [
        d.file(
          'trusted_root.json',
          '{"mediaType":"cache_test","certificateAuthorities":[]}',
        ),
      ]),
    ]).create();

    final cache = SystemCache(rootDir: p.join(d.sandbox, 'cache'));
    final root = loadTrustedRoot(cache: cache);

    expect(root!['mediaType'], equals('cache_test'));
    expect(root['certificateAuthorities'], isEmpty);
  });

  test('returns null when no override or cache is found', () {
    final root = loadTrustedRoot();
    expect(root, isNull);
  });

  test(
    'detects missing or expired TUF cache and lazily refreshes on get',
    () async {
      final cache = SystemCache(rootDir: p.join(d.sandbox, 'cache'));
      final now = DateTime.utc(2026, 10, 7, 12);

      // 1. Missing cache is reported as expired.
      expect(
        isTrustedRootCacheExpired(
          cacheDir: cache.sigstoreTufCacheDir,
          cachePath: cache.sigstoreTrustedRootPath,
          now: now,
        ),
        isTrue,
      );

      var refreshCount = 0;
      await refreshTrustedRootIfNeeded(
        cache: cache,
        refresher: (mirrorUrl, cacheDir) {
          refreshCount++;
          final futureExpiry = DateTime.now().toUtc().add(
            const Duration(days: 7),
          );
          File(
            p.join(cacheDir, '5.root.json'),
          ).writeAsStringSync(_tufRoleJson(version: 5, expires: futureExpiry));
          File(p.join(cacheDir, 'timestamp.json')).writeAsStringSync(
            _tufRoleJson(version: 100, expires: futureExpiry),
          );
          return '{"mediaType":"v5_root","certificateAuthorities":[]}';
        },
      );
      expect(refreshCount, equals(1));
      expect(readMaxTufRootVersion(cache.sigstoreTufCacheDir), equals(5));
      expect(loadTrustedRoot(cache: cache)!['mediaType'], equals('v5_root'));

      // 2. Fresh cache is NOT refreshed when force is false (`dart pub get`).
      await refreshTrustedRootIfNeeded(
        cache: cache,
        refresher: (mirrorUrl, cacheDir) {
          refreshCount++;
          return '{"mediaType":"v6_root","certificateAuthorities":[]}';
        },
      );
      expect(refreshCount, equals(1));

      // 3. Expired timestamp.json triggers a lazy refresh on `dart pub get`.
      final pastExpiry = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      File(
        p.join(cache.sigstoreTufCacheDir, 'timestamp.json'),
      ).writeAsStringSync(_tufRoleJson(version: 100, expires: pastExpiry));
      expect(
        isTrustedRootCacheExpired(
          cacheDir: cache.sigstoreTufCacheDir,
          cachePath: cache.sigstoreTrustedRootPath,
        ),
        isTrue,
      );

      await refreshTrustedRootIfNeeded(
        cache: cache,
        refresher: (mirrorUrl, cacheDir) {
          refreshCount++;
          final futureExpiry = DateTime.now().toUtc().add(
            const Duration(days: 7),
          );
          File(
            p.join(cacheDir, '6.root.json'),
          ).writeAsStringSync(_tufRoleJson(version: 6, expires: futureExpiry));
          File(p.join(cacheDir, 'timestamp.json')).writeAsStringSync(
            _tufRoleJson(version: 101, expires: futureExpiry),
          );
          return '{"mediaType":"v6_root","certificateAuthorities":[]}';
        },
      );
      expect(refreshCount, equals(2));
      expect(readMaxTufRootVersion(cache.sigstoreTufCacheDir), equals(6));
      expect(loadTrustedRoot(cache: cache)!['mediaType'], equals('v6_root'));
    },
  );

  test(
    'never downgrades below highest cached TUF root version or falls back to '
    'bundled root',
    () async {
      final cache = SystemCache(rootDir: p.join(d.sandbox, 'cache'));
      final futureExpiry = DateTime.now().toUtc().add(const Duration(days: 7));

      // Seed cache with TUF root v10.
      await refreshTrustedRoot(
        cacheDir: cache.sigstoreTufCacheDir,
        cachePath: cache.sigstoreTrustedRootPath,
        refresher: (mirrorUrl, cacheDir) {
          File(
            p.join(cacheDir, '10.root.json'),
          ).writeAsStringSync(_tufRoleJson(version: 10, expires: futureExpiry));
          File(
            p.join(cacheDir, 'timestamp.json'),
          ).writeAsStringSync(_tufRoleJson(version: 50, expires: futureExpiry));
          return '{"mediaType":"v10_root","certificateAuthorities":[]}';
        },
      );
      expect(readMaxTufRootVersion(cache.sigstoreTufCacheDir), equals(10));

      // Attempt to downgrade to TUF root v9: must throw DataException, restore
      // v10 metadata on disk, and preserve v10 trusted_root.json.
      await expectLater(
        refreshTrustedRootIfNeeded(
          cache: cache,
          force: true,
          refresher: (mirrorUrl, cacheDir) {
            File(p.join(cacheDir, '10.root.json')).deleteSync();
            File(p.join(cacheDir, '9.root.json')).writeAsStringSync(
              _tufRoleJson(version: 9, expires: futureExpiry),
            );
            return '{"mediaType":"v9_downgraded","certificateAuthorities":[]}';
          },
        ),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            contains(
              'Refusing to downgrade Sigstore TUF root version from 10 to 9',
            ),
          ),
        ),
      );
      expect(readMaxTufRootVersion(cache.sigstoreTufCacheDir), equals(10));
      expect(loadTrustedRoot(cache: cache)!['mediaType'], equals('v10_root'));

      // If trusted_root.json is missing while TUF metadata (v10) is on disk,
      // loadTrustedRootJson must throw DataException rather than returning null
      // and silently downgrading to the SDK-bundled root.
      File(cache.sigstoreTrustedRootPath).deleteSync();
      expect(
        () => loadTrustedRoot(cache: cache),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            contains('Refusing to fall back to the bundled trusted root'),
          ),
        ),
      );
    },
  );
}
