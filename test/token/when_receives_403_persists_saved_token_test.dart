// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  setUp(d.validPackage.create);

  test('when receives 403 response persists saved token', () async {
    await servePackages();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalPackageServer.url, 'token': 'access token'},
      ]
    }).create();
    var pub = await startPublish(globalPackageServer, authMethod: 'token');
    await confirmPublish(pub);

    globalPackageServer.expect('GET', '/api/packages/versions/new', (request) {
      return shelf.Response(403);
    });

    await pub.shouldExit(65);

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': globalPackageServer.url, 'token': 'access token'},
      ]
    }).validate();
  });
}
