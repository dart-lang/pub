// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
      'with server-rejected credentials, authenticates again and saves '
      'credentials.json', () async {
    await d.validPackage.create();
    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);

    await confirmPublish(pub);

    globalPackageServer.expect('GET', '/api/packages/versions/new', (request) {
      return shelf.Response(401,
          body: jsonEncode({
            'error': {'message': 'your token sucks'}
          }),
          headers: {
            'www-authenticate': 'Bearer error="invalid_token",'
                ' error_description="your token sucks"'
          });
    });

    await expectLater(
        pub.stderr, emits('OAuth2 authorization failed (your token sucks).'));
    expect(pub.stdout, emits(startsWith('Uploading...')));
    await pub.kill();
  });
}
