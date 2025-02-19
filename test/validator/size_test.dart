// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub/src/validator/size.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Future<void> expectSizeValidationHint(Matcher matcher) async {
  await expectValidationDeprecated(
    SizeValidator.new,
    size: 100 * (1 << 20) + 1,
    hints: contains(matcher),
  );
}

void main() {
  test('ho hint if package is <= 100 MB', () async {
    await d.validPackage().create();

    await expectValidationDeprecated(SizeValidator.new, size: 100);
    await expectValidationDeprecated(SizeValidator.new, size: 100 * (1 << 20));
  });

  group('hints if package is more than 100 MB', () {
    test(
      'package is not under source control and no .gitignore exists',
      () async {
        await d.validPackage().create();

        await expectSizeValidationHint(contains('Your package is 100.0 MB.'));
      },
    );

    test('package is not under source control and .gitignore exists', () async {
      await d.validPackage().create();
      await d.dir(appPath, [d.file('.gitignore', 'ignored')]).create();

      await expectSizeValidationHint(
        allOf(
          contains('Your package is 100.0 MB.'),
          contains(
            'Your .gitignore has no effect since your project '
            'does not appear to be in version control.',
          ),
        ),
      );
    });

    test('package is under source control and no .gitignore exists', () async {
      await d.validPackage().create();
      await d.git(appPath).create();

      await expectSizeValidationHint(
        allOf(
          contains('Your package is 100.0 MB.'),
          contains(
            'Consider adding a .gitignore to avoid including '
            'temporary files.',
          ),
        ),
      );
    });

    test('package is under source control and .gitignore exists', () async {
      await d.validPackage().create();
      await d.git(appPath, [d.file('.gitignore', 'ignored')]).create();

      await expectSizeValidationHint(contains('Your package is 100.0 MB.'));
    });
  });
}
