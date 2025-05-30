// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('with an expired credentials.json, refreshes and saves the '
      'refreshed access token to credentials.json', () async {
    await d.validPackage().create();

    await servePackages();
    await d
        .credentialsFile(
          globalServer,
          'access-token',
          refreshToken: 'refresh token',
          expiration: DateTime.now().subtract(const Duration(hours: 1)),
        )
        .create();

    final pub = await startPublish(globalServer);
    await confirmPublish(pub);

    globalServer.expect('POST', '/token', (request) {
      return request.readAsString().then((body) {
        expect(
          body,
          matches(RegExp(r'(^|&)refresh_token=refresh\+token(&|$)')),
        );

        return shelf.Response.ok(
          jsonEncode({
            'access_token': 'new access token',
            'token_type': 'bearer',
          }),
          headers: {'content-type': 'application/json'},
        );
      });
    });

    globalServer.expect('GET', '/api/packages/versions/new', (request) {
      expect(
        request.headers,
        containsPair('authorization', 'Bearer new access token'),
      );

      return shelf.Response(200);
    });

    await pub.shouldExit();

    await d
        .credentialsFile(
          globalServer,
          'new access token',
          refreshToken: 'refresh token',
        )
        .validate();
  });
}
