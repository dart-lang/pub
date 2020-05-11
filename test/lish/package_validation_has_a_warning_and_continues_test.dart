// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('package validation has a warning and continues', () async {
    var pkg =
        packageMap('test_pkg', '1.0.0', null, null, {'sdk': '>=1.8.0 <2.0.0'});
    pkg['author'] = 'Natalie Weizenbaum';
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);
    pub.stdin.writeln('y');
    handleUploadForm(globalPackageServer);
    handleUpload(globalPackageServer);

    globalPackageServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(jsonEncode({
        'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
      }));
    });

    await pub.shouldExit(exit_codes.SUCCESS);
    expect(pub.stdout, emitsThrough('Package test_pkg 1.0.0 uploaded!'));
  });
}
