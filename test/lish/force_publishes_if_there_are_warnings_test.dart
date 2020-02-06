// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('--force publishes if there are warnings', () async {
    var pkg =
        packageMap('test_pkg', '1.0.0', null, null, {'sdk': '>=1.8.0 <2.0.0'});
    pkg['dependencies'] = {'foo': 'any'};
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    var server = await ShelfTestServer.create();
    await d.credentialsFile(server, 'access token').create();
    var pub = await startPublish(server, args: ['--force']);

    handleUploadForm(server);
    handleUpload(server);

    server.handler.expect('GET', '/create', (request) {
      return shelf.Response.ok(jsonEncode({
        'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
      }));
    });

    await pub.shouldExit(exit_codes.SUCCESS);
    expect(
      pub.stderr,
      emitsThrough('Package validation found the following potential issue:'),
    );
    expect(
        pub.stderr,
        emitsLines(
            '* Your dependency on "foo" should have a version constraint.\n'
            '  Without a constraint, you\'re promising to support all future versions of "foo".'));
    expect(pub.stdout, emitsThrough('Package test_pkg 1.0.0 uploaded!'));
  });
}
