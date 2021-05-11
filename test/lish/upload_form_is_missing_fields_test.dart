// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:convert';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('upload form is missing fields', () async {
    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);

    await confirmPublish(pub);

    var body = {'url': 'http://example.com/upload'};
    handleUploadForm(globalPackageServer, body);
    expect(pub.stderr, emits('Invalid server response:'));
    expect(pub.stderr, emits(jsonEncode(body)));
    await pub.shouldExit(1);
  });
}
