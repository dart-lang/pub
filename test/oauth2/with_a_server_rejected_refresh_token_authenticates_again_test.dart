// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  // Regression test for issue 8849.
  test(
      'with a server-rejected refresh token, authenticates again and '
      'saves credentials.json', () async {
    await d.validPackage.create();

    await servePackages();
    await d
        .credentialsFile(globalPackageServer, 'access token',
            refreshToken: 'bad refresh token',
            expiration: DateTime.now().subtract(Duration(hours: 1)))
        .create();

    var pub = await startPublish(globalPackageServer);

    globalPackageServer.expect('POST', '/token', (request) {
      return request.read().drain().then((_) {
        return shelf.Response(400,
            body: jsonEncode({'error': 'invalid_request'}),
            headers: {'content-type': 'application/json'});
      });
    });

    await confirmPublish(pub);

    await expectLater(pub.stdout, emits(startsWith('Uploading...')));
    await authorizePub(pub, globalPackageServer, 'new access token');

    var done = Completer();
    globalPackageServer.expect('GET', '/api/packages/versions/new',
        (request) async {
      expect(request.headers,
          containsPair('authorization', 'Bearer new access token'));

      // kill pub and complete test
      await pub.kill();
      done.complete();

      return shelf.Response(200);
    });

    await done.future;
  });
}
