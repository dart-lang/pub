// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('with --skip-validation dependency resolution '
      'and validations are skipped.', () async {
    await servePackages();
    await d.validPackage().create();
    await d.dir(appPath, [
      d.validPubspec(
        extras: {
          // Dependency cannot be resolved.
          'dependencies': {'foo': 'any'},
        },
      ),
    ]).create();
    // It is an error to publish without a LICENSE file.
    File(d.path(p.join(appPath, 'LICENSE'))).deleteSync();
    await d.credentialsFile(globalServer, 'access-token').create();

    await servePackages();
    final pub = await startPublish(globalServer, args: ['--skip-validation']);

    await confirmPublish(pub);

    handleUploadForm(globalServer);
    handleUpload(globalServer);

    globalServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'},
        }),
      );
    });
    await pub.shouldExit(exit_codes.SUCCESS);
  });
}
