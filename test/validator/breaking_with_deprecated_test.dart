// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('should only warn when publishing a breaking release ', () async {
    final server = await servePackages();
    await d.dir(appPath, [
      d.validPubspec(extras: {'version': '2.0.0'}),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 2.0.0\nFirst version\n'),
      d.dir('lib', [
        d.file(
          'test_pkg.dart',
          "@Deprecated('Stop using this please') int i = 1;",
        ),
        d.dir('src', [
          d.file(
            'support.dart',
            "@Deprecated('Stop using this please') class B {}",
          ),
        ])
      ]),
    ]).create();
    // No earlier versions, so not a breaking release.
    await expectValidation();
    server.serve('test_pkg', '1.0.0');
    await expectValidationWarning(
      allOf(
        contains('Consider removing this deprecated declaration.'),
        contains('int i'),
        isNot(contains('class B')),
      ),
    );
  });
}
