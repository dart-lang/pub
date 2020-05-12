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

  test('package creation provides a malformed success', () async {
    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);

    await confirmPublish(pub);
    handleUploadForm(globalPackageServer);
    handleUpload(globalPackageServer);

    var body = {'success': 'Your package was awesome.'};
    globalPackageServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(jsonEncode(body));
    });

    expect(pub.stderr, emits('Invalid server response:'));
    expect(pub.stderr, emits(jsonEncode(body)));
    await pub.shouldExit(1);
  });
}
