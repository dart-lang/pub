// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  // Symlinks are not followed on Windows,
  // because 7-Zip does not provide such an option.
  if (Platform.isWindows) return;

  test('publish follows file symlinks', () async {
    await d.validPackage.create();

    var appRoot = p.join(d.sandbox, appPath);

    // hidden target file, so it is excluded
    const target = '.target';
    final data = Uint8List(1 << 20); // 1 MiB
    final rng = math.Random();
    data.setAll(0, Iterable.generate(data.length, (i) => rng.nextInt(256)));
    File(p.join(appRoot, target)).writeAsBytesSync(data);

    // non-hidden link that points to the target file
    const link = 'link';
    Link(p.join(appRoot, link)).createSync(target);

    await servePackages();
    await d.credentialsFile(globalPackageServer, 'access token').create();
    var pub = await startPublish(globalPackageServer);

    await confirmPublish(pub);
    handleUploadForm(globalPackageServer);

    var packageSize = 0;

    globalPackageServer.expect('POST', '/upload', (request) {
      return request
          .read()
          .fold(0, (size, bytes) => size + bytes.length)
          .then((size) => packageSize = size)
          .then((_) => globalPackageServer.url)
          .then((url) => shelf.Response.found(Uri.parse(url).resolve('/create')));
    });

    globalPackageServer.expect('GET', '/create', (request) {
      return shelf.Response.ok(jsonEncode({
        'success': {'message': 'Package test_pkg 1.0.0 uploaded!'}
      }));
    });

    expect(pub.stdout, emits(startsWith('Uploading...')));
    expect(pub.stdout, emits('Package test_pkg 1.0.0 uploaded!'));
    await pub.shouldExit(exit_codes.SUCCESS);

    // if the link has been followed, the body contains the random data
    expect(packageSize, greaterThan(data.length));
  });
}
