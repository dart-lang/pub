// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  setUp(d.validPackage.create);

  test('preview package validation has a warning', () async {
    var pkg =
        packageMap('test_pkg', '1.0.0', null, null, {'sdk': '>=1.8.0 <2.0.0'});
    pkg['dependencies'] = {'foo': 'any'};
    await d.dir(appPath, [d.pubspec(pkg)]).create();

    var server = await ShelfTestServer.create();
    var pub = await startPublish(server, args: ['--dry-run']);

    await pub.shouldExit(exit_codes.DATA);
    expect(
      pub.stderr,
      emitsThrough('Package validation found the following potential issue:'),
    );
    expect(
        pub.stderr,
        emitsLines(
            '* Your dependency on "foo" should have a version constraint.\n'
            '  Without a constraint, you\'re promising to support all future versions of "foo".\n'
            '\n'
            'Package has 1 warning.'));
  });
}
