// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('cloud storage upload provides an error', () async {
    await servePackages();
    await d.validPackage().create();
    await d.credentialsFile(globalServer, 'access-token').create();
    final pub = await startPublish(globalServer);

    await confirmPublish(pub);
    handleUploadForm(globalServer);

    globalServer.expect('POST', '/upload', (request) {
      return request.read().drain<void>().then((_) {
        return shelf.Response.notFound(
          // Actual example of an error code we get from GCS
          "<?xml version='1.0' encoding='UTF-8'?><Error><Code>EntityTooLarge</Code><Message>Your proposed upload is larger than the maximum object size specified in your Policy Document.</Message><Details>Content-length exceeds upper bound on range</Details></Error>",
          headers: {'content-type': 'application/xml'},
        );
      });
    });

    expect(
      pub.stderr,
      emits(
        'Server error code: EntityTooLarge',
      ),
    );
    expect(
      pub.stderr,
      emits(
        'Server message: Your proposed upload is larger than the maximum object size specified in your Policy Document.',
      ),
    );
    expect(
      pub.stderr,
      emits('Server details: Content-length exceeds upper bound on range'),
    );

    expect(pub.stderr, emits('Failed to upload the package.'));
    await pub.shouldExit(1);
  });
}
