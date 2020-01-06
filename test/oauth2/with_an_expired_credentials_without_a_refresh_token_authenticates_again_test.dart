// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test(
      'with an expired credentials.json without a refresh token, '
      'authenticates again and saves credentials.json', () async {
    await d.validPackage.create();

    var server = await ShelfTestServer.create();
    await d
        .credentialsFile(server, 'access token',
            expiration: DateTime.now().subtract(Duration(hours: 1)))
        .create();

    var pub = await startPublish(server);
    await confirmPublish(pub);

    await expectLater(
        pub.stderr,
        emits("Pub's authorization to upload packages has expired and "
            "can't be automatically refreshed."));
    await authorizePub(pub, server, 'new access token');

    server.handler.expect('GET', '/api/packages/versions/new', (request) {
      expect(request.headers,
          containsPair('authorization', 'Bearer new access token'));

      return shelf.Response(200);
    });

    // After we give pub an invalid response, it should crash. We wait for it to
    // do so rather than killing it so it'll write out the credentials file.
    await pub.shouldExit(1);

    await d.credentialsFile(server, 'new access token').validate();
  });
}
