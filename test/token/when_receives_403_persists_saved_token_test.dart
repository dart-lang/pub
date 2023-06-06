// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('when receives 403 response persists saved token', () async {
    await d.validPackage().create();
    final server = await servePackages();
    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': server.url, 'token': 'access-token'},
      ]
    }).create();
    var pub = await startPublish(server, overrideDefaultHostedServer: false);
    await confirmPublish(pub);

    server.expect('GET', '/api/packages/versions/new', (request) {
      return shelf.Response(403);
    });

    await pub.shouldExit(65);

    await d.tokensFile({
      'version': 1,
      'hosted': [
        {'url': server.url, 'token': 'access-token'},
      ]
    }).validate();
  });
}
