// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exceptions.dart';
import 'package:pub/src/path.dart';
import 'package:pub/src/sigstore/trusted_root.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;

void main() {
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

  test('ignores a corrupt trusted_root.json in the pub cache', () async {
    // The cached root is not something the user wrote: a corrupt one must not
    // fail every attested package, the built-in root is used instead.
    await d.dir('cache', [
      d.dir('sigstore', [d.file('trusted_root.json', '{not json')]),
    ]).create();

    final cache = SystemCache(rootDir: p.join(d.sandbox, 'cache'));
    expect(loadTrustedRootJson(cache: cache), isNull);
    expect(loadTrustedRoot(cache: cache), isNull);
  });

  test('returns null when no override or cache is found', () {
    final root = loadTrustedRoot();
    expect(root, isNull);
  });
}
