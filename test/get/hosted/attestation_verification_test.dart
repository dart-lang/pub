// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/exit_codes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../sigstore/test_fixtures.dart';
import '../../test_pub.dart';

void main() {
  test('proceeds when no attestation is served by repository', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d
        .appDir(
          dependencies: {
            'foo': {'hosted': server.url, 'version': '^1.0.0'},
          },
        )
        .create();

    await pubGet();
    final cacheDir = server.pathInCache('foo', '1.0.0');
    expect(Directory(cacheDir).existsSync(), isTrue);
  });

  test(
    'pub get fails when attestation does not match package archive',
    () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0', slsaLevel: 2);

      server.handle('/api/packages/foo/versions/1.0.0/attestation', (request) {
        return Response.ok(
          sampleBundleJson,
          headers: {'content-type': 'application/json; charset="utf-8"'},
        );
      });

      await d
          .appDir(
            dependencies: {
              'foo': {'hosted': server.url, 'version': '^1.0.0'},
            },
          )
          .create();

      await pubGet(
        error: contains('failed Sigstore attestation verification'),
        exitCode: TEMP_FAIL,
      );
    },
  );
}
