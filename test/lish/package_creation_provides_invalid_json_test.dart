// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';
import 'package:scheduled_test/scheduled_server.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  setUp(d.validPackage.create);

  integration('package creation provides invalid JSON', () {
    var server = new ScheduledServer();
    d.credentialsFile(server, 'access token').create();
    var pub = startPublish(server);

    confirmPublish(pub);
    handleUploadForm(server);
    handleUpload(server);

    server.handle('GET', '/create', (request) {
      return new shelf.Response.ok('{not json');
    });

    pub.stderr.expect(emitsLines('Invalid server response:\n'
        '{not json'));
    pub.shouldExit(1);
  });
}
