// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as td;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

/// Describes a package with dot-files in tree.
td.DirectoryDescriptor get validPackageWithDotFiles => d.dir(appPath, [
      d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0 <=2.0.0'),
      td.dir('.dart_tool', [td.file('package_config.json')]),
      td.dir('.github', [td.file('ignored.yml')]),
      td.file('.gitignore'),
      td.file('LICENSE', 'Eh, do what you want.'),
      td.file('README.md', "This package isn't real."),
      td.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      td.dir('lib', [td.file('test_pkg.dart', 'int i = 1;')])
    ]);

void main() {
  setUp(validPackageWithDotFiles.create);

  test('Check if package doesn\'t include dot-files', () async {
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

    expect(pub.stdout, emits('test_pkg.dart'));
    expect(pub.stdout, neverEmits('.dart_tool'));
    expect(pub.stdout, neverEmits('.github'));
    await pub.shouldExit(exit_codes.SUCCESS);
  });
}
