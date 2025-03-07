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
  test('upload form provides an error, that is sanitized', () async {
    await servePackages();
    await d.validPackage().create();
    await d.credentialsFile(globalServer, 'access-token').create();
    final pub = await startPublish(globalServer);

    await confirmPublish(pub);

    globalServer.expect('GET', '/api/packages/versions/new', (request) async {
      return shelf.Response.notFound(
        jsonEncode({
          'error': {
            'message': 'your request\u0000sucked',
          }, // The \u0000 should be sanitized to a space.
        }),
      );
    });

    expect(pub.stderr, emits('Message from server: your request sucked'));
    await pub.shouldExit(1);
  });

  test('upload fails with xml message', () async {
    await servePackages();
    await d.validPackage().create();
    await d.credentialsFile(globalServer, 'access-token').create();
    handleUploadForm(globalServer);

    globalServer.expect('POST', '/upload', (request) async {
      return shelf.Response.badRequest(
        headers: {'Content-Type': 'application/xml'},
        body: '''
<?xml version='1.0' encoding='utf-8'?>
<Error>
  <Code>BucketNameUnavailable</Code>
  <Message>
    The requested bucket name is not available.
  </Message>
</Error>
''',
      );
    });

    final pub = await startPublish(globalServer);
    await confirmPublish(pub);

    expect(pub.stderr, emits('Server error code: BucketNameUnavailable'));
    expect(
      pub.stderr,
      emits('Server message: The requested bucket name is not available.'),
    );
    await pub.shouldExit(1);
  });

  test('upload fails with json message', () async {
    await servePackages();
    await d.validPackage().create();
    await d.credentialsFile(globalServer, 'access-token').create();
    handleUploadForm(globalServer);

    globalServer.expect('POST', '/upload', (request) async {
      return shelf.Response.badRequest(
        body: jsonEncode({
          'error': {
            'message': 'your request\u0000sucked',
          }, // The \u0000 should be sanitized to a space.
        }),
      );
    });

    final pub = await startPublish(globalServer);
    await confirmPublish(pub);

    expect(pub.stderr, emits('Message from server: your request sucked'));
    await pub.shouldExit(1);
  });
}
