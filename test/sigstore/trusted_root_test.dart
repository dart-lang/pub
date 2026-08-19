// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exceptions.dart';
import 'package:pub/src/path.dart';
import 'package:pub/src/sigstore/trusted_root.dart';
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

    expect(root['mediaType'], equals('test'));
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
}
