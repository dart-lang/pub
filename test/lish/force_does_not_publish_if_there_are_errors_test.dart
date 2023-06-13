// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--force does not publish if there are errors', () async {
    await servePackages();
    await d.validPackage().create();
    // It is an error to publish without a LICENSE file.
    File(d.path(p.join(appPath, 'LICENSE'))).deleteSync();

    await servePackages();
    var pub = await startPublish(globalServer, args: ['--force']);

    await pub.shouldExit(exit_codes.DATA);
    expect(
      pub.stderr,
      emitsThrough(
        "Sorry, your package is missing a requirement and can't be published yet.",
      ),
    );
  });
}
