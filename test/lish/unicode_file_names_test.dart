// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('archives and uploads a package with unicode filenames', () async {
    await d.validPackage().create();
    await d.dir(appPath, [d.file('🦄.yml')]).create();

    await servePackages();
    await d.credentialsFile(globalServer, 'access-token').create();
    var pub = await startPublish(globalServer);

    await confirmPublish(pub);
    handleUploadForm(globalServer);
    handleUpload(globalServer);

    globalServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
        }),
      );
    });

    expect(pub.stdout, emits(startsWith('Uploading...')));
    expect(pub.stdout, emits('Package test_pkg 1.0.0 uploaded!'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });

  test('Can download and unpack package with unicode in file-name', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', contents: [d.file('🦄.yml')]);
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await pubGet();
    await d.hostedCache([
      d.dir('foo-1.0.0', [d.file('🦄.yml')]),
    ]).validate();
  });
}
