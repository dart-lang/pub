// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('package creation provides an error', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub = await startPublish(server);

    await confirmPublish(pub);
    handleUploadForm(server);
    handleUpload(server);

    server.handler.expect('GET', '/create', (request) {
      return shelf.Response.notFound(jsonEncode({
        'error': {'message': 'Your package was too boring.'}
      }));
    });

    expect(pub.stderr, emits('Your package was too boring.'));
    await pub.shouldExit(1);
  });
}
