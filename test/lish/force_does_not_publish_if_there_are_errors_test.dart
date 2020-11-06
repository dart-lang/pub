// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  setUp(d.validPackage.create);

  test('--force does not publish if there are errors', () async {
    await d.dir(appPath, [
      d.rawPubspec({
        'name': 'test_pkg',
        'homepage': 'http://pub.dartlang.org',
        'version': '1.0.0',
      }),
    ]).create();

    await servePackages();
    var pub = await startPublish(globalPackageServer, args: ['--force']);

    await pub.shouldExit(exit_codes.DATA);
    expect(
        pub.stderr,
        emitsThrough('Sorry, your package is missing some '
            "requirements and can't be published yet."));
  });
}
