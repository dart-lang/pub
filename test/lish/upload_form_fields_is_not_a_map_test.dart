// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  setUp(d.validPackage.create);

  test('upload form fields is not a map', () async {
    await servePackages();
    await d.credentialsFile(globalServer, 'access token').create();
    var pub = await startPublish(globalServer);

    await confirmPublish(pub);

    var body = {'url': 'http://example.com/upload', 'fields': 12};
    handleUploadForm(globalServer, body: body);
    expect(pub.stderr, emits('Invalid server response:'));
    expect(pub.stderr, emits(jsonEncode(body)));
    await pub.shouldExit(1);
  });
}
