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

  test('package creation provides a malformed error', () async {
    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub = await startPublish(server);

    await confirmPublish(pub);
    handleUploadForm(server);
    handleUpload(server);

    var body = {'error': 'Your package was too boring.'};
    server.handler.expect('GET', '/create', (request) {
      return shelf.Response.notFound(jsonEncode(body));
    });

    expect(pub.stderr, emits('Invalid server response:'));
    expect(pub.stderr, emits(jsonEncode(body)));
    await pub.shouldExit(1);
  });
}
