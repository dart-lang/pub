// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('package creation provides an error', () async {
    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);

    await confirmPublish(pub);
    handleUploadForm(globalPackageServer);
    handleUpload(globalPackageServer);

    globalPackageServer.expect('GET', '/create', (request) {
      return shelf.Response.notFound(jsonEncode({
        'error': {'message': 'Your package was too boring.'}
      }));
    });

    expect(pub.stderr, emits('Your package was too boring.'));
    await pub.shouldExit(1);
  });
}
