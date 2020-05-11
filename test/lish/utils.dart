// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../test_pub.dart';

void handleUploadForm(PackageServer server, [Map body]) {
  server.expect('GET', '/api/packages/versions/new', (request) {
    expect(
        request.headers, containsPair('authorization', 'Bearer access token'));

    body ??= {
      'url': Uri.parse(server.url).resolve('/upload').toString(),
      'fields': {'field1': 'value1', 'field2': 'value2'}
    };

    return shelf.Response.ok(jsonEncode(body),
        headers: {'content-type': 'application/json'});
  });
}

void handleUpload(PackageServer server) {
  server.expect('POST', '/upload', (request) {
    // TODO(nweiz): Once a multipart/form-data parser in Dart exists, validate
    // that the request body is correctly formatted. See issue 6952.
    return request
        .read()
        .drain()
        .then((_) => server.url)
        .then((url) => shelf.Response.found(Uri.parse(url).resolve('/create')));
  });
}
