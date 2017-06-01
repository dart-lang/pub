// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(d.validPackage.create);

  test('--force does not publish if there are errors', () async {
    var pkg = packageMap("test_pkg", "1.0.0");
    pkg.remove("homepage");
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    var server = await ShelfTestServer.create();
    var pub = await startPublish(server, args: ['--force']);

    await pub.shouldExit(exit_codes.DATA);
    expect(
        pub.stderr,
        emitsThrough("Sorry, your package is missing a "
            "requirement and can't be published yet."));
  });
}
