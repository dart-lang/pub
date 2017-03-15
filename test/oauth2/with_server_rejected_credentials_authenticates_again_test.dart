// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:scheduled_test/scheduled_server.dart';
import 'package:scheduled_test/scheduled_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration(
      'with server-rejected credentials, authenticates again and saves '
      'credentials.json', () {
    d.validPackage.create();
    var server = new ScheduledServer();
    d.credentialsFile(server, 'access token').create();
    var pub = startPublish(server);

    confirmPublish(pub);

    server.handle('GET', '/api/packages/versions/new', (request) {
      return new shelf.Response(401,
          body: JSON.encode({
            'error': {'message': 'your token sucks'}
          }),
          headers: {
            'www-authenticate': 'Bearer error="invalid_token",'
                ' error_description="your token sucks"'
          });
    });

    pub.stderr.expect('OAuth2 authorization failed (your token sucks).');
    pub.stdout.expect(startsWith('Uploading...'));
    pub.kill();
  });
}
