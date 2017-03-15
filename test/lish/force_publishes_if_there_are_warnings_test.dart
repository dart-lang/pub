// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_server.dart';
import 'package:scheduled_test/scheduled_stream.dart';
import 'package:scheduled_test/scheduled_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  setUp(d.validPackage.create);

  integration('--force publishes if there are warnings', () {
    var pkg = packageMap("test_pkg", "1.0.0");
    pkg["author"] = "Natalie Weizenbaum";
    d.dir(appPath, [d.pubspec(pkg)]).create();

    var server = new ScheduledServer();
    d.credentialsFile(server, 'access token').create();
    var pub = startPublish(server, args: ['--force']);

    handleUploadForm(server);
    handleUpload(server);

    server.handle('GET', '/create', (request) {
      return new shelf.Response.ok(JSON.encode({
        'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
      }));
    });

    pub.shouldExit(exit_codes.SUCCESS);
    pub.stderr.expect(consumeThrough('Suggestions:'));
    pub.stderr.expect(emitsLines(
        '* Author "Natalie Weizenbaum" in pubspec.yaml should have an email '
        'address\n'
        '  (e.g. "name <email>").'));
    pub.stdout.expect(consumeThrough('Package test_pkg 1.0.0 uploaded!'));
  });
}
