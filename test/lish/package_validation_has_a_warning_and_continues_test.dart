// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
  test('package validation has a warning and continues', () async {
    await servePackages();
    await d.validPackage().create();
    // Publishing without a README.md gives a warning.
    File(d.path(p.join(appPath, 'README.md'))).deleteSync();

    await servePackages();
    await d.credentialsFile(globalServer, 'access-token').create();
    var pub = await startPublish(globalServer);
    expect(pub.stdout, emitsThrough(startsWith('Package has 1 warning.')));
    pub.stdin.writeln('y');
    handleUploadForm(globalServer);
    handleUpload(globalServer);

    globalServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(
        jsonEncode({
          'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
        }),
      );
    });

    await pub.shouldExit(exit_codes.SUCCESS);
    expect(pub.stdout, emitsThrough('Package test_pkg 1.0.0 uploaded!'));
  });
}
