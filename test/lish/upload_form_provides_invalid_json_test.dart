// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('upload form provides invalid JSON', () async {
    await servePackages();
    await d.validPackage().create();
    await servePackages();
    await d.credentialsFile(globalServer, 'access-token').create();
    var pub = await startPublish(globalServer);

    await confirmPublish(pub);

    globalServer.expect(
      'GET',
      '/api/packages/versions/new',
      (request) => shelf.Response.ok('{not json'),
    );

    expect(
      pub.stderr,
      emitsLines('Invalid server response:\n'
          '{not json'),
    );
    await pub.shouldExit(1);
  });
}
