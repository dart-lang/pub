// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test(
      'with no credentials.json, authenticates and saves '
      'credentials.json', () async {
    await d.validPackage.create();

    await servePackages();
    var pub = await startPublish(globalPackageServer);
    await confirmPublish(pub);
    await authorizePub(pub, globalPackageServer);

    globalPackageServer.expect('GET', '/api/packages/versions/new', (request) {
      expect(request.headers,
          containsPair('authorization', 'Bearer access token'));

      return shelf.Response(200);
    });

    // After we give pub an invalid response, it should crash. We wait for it to
    // do so rather than killing it so it'll write out the credentials file.
    await pub.shouldExit(1);

    await d.credentialsFile(globalPackageServer, 'access token').validate();
  });
}
