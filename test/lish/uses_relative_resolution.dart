// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(d.validPackage.create);

  test('resolves URL relative to base URI', () async {
    var server = await ShelfTestServer.create();
    var baseUri = server.url.resolve('/sub/dir');
    await d.credentialsFile(server, 'access token').create();

    Uri resolveUrl(String path) =>
        baseUri.replace(path: p.join(baseUri.path, path));

    // This code is from `startPublish`, but had to be adapted, as the
    // original resolves the absolute path /token, whereas we are testing
    // relative resolution.
    // var tokenEndpoint = server.url.resolve('token').toString();
    var args = ['lish'];
    var pub = await startPub(
        args: args, environment: {'PUB_HOSTED_URL': baseUri.toString()});

    await confirmPublish(pub);

    // Because we are testing that the URL for publishing is resolved relative to the
    // base URL, instead of using handleUploadForm(...), we expect that Pub sends
    // a request to /sub/dir/api/..., not /api/...
    server.handler.expect('GET', '/sub/dir/api/packages/versions/new',
        (request) {
      expect(request.headers,
          containsPair('authorization', 'Bearer access token'));
      var body = {
        'url': resolveUrl('upload').toString(),
        'fields': {'field1': 'value1', 'field2': 'value2'}
      };
      return shelf.Response.ok(jsonEncode(body),
          headers: {'content-type': 'application/json'});
    });

    // Likewise, we can't use handleUpload(...), because that expects a request to
    // /upload, not /sub/dir/upload, which is what we are testing for.
    server.handler.expect('POST', '/sub/dir/upload', (request) {
      // Note: The below TODO was present in ./archives_and_uploads_a_package_test.dart,
      // where the majority of this testing code is taken from, so the comment was left here
      // as well.
      //
      // TODO(nweiz): Once a multipart/form-data parser in Dart exists, validate
      // that the request body is correctly formatted. See issue 6952.
      return request
          .read()
          .drain()
          .then((_) => server.url)
          .then((url) => shelf.Response.found(resolveUrl('create')));
    });

    server.handler.expect('GET', '/sub/dir/create', (request) {
      return shelf.Response.ok(jsonEncode({
        'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
      }));
    });

    expect(pub.stdout, emits(startsWith('Uploading...')));
    expect(pub.stdout, emits('Package test_pkg 1.0.0 uploaded!'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });
}
