// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:pub/src/validator/size.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

ValidatorCreator size(int size) {
  return (entrypoint) => SizeValidator(entrypoint, Future.value(size));
}

void expectSizeValidationError(Matcher matcher) {
  expect(validatePackage(size(100 * math.pow(2, 20) + 1)),
      completion(pairOf(contains(matcher), anything)));
}

void main() {
  test('considers a package valid if it is <= 100 MB', () async {
    await d.validPackage.create();

    expectNoValidationError(size(100));
    expectNoValidationError(size(100 * math.pow(2, 20)));
  });

  group('considers a package invalid if it is more than 100 MB', () {
    test('package is not under source control and no .gitignore exists',
        () async {
      await d.validPackage.create();

      expectSizeValidationError(
          equals('Your package is 100.0 MB. Hosted packages must '
              'be smaller than 100 MB.'));
    });

    test('package is not under source control and .gitignore exists', () async {
      await d.validPackage.create();
      await d.dir(appPath, [d.file('.gitignore', 'ignored')]).create();

      expectSizeValidationError(allOf(
          contains('Hosted packages must be smaller than 100 MB.'),
          contains('Your .gitignore has no effect since your project '
              'does not appear to be in version control.')));
    });

    test('package is under source control and no .gitignore exists', () async {
      await d.validPackage.create();
      await d.git(appPath).create();

      expectSizeValidationError(allOf(
          contains('Hosted packages must be smaller than 100 MB.'),
          contains('Consider adding a .gitignore to avoid including '
              'temporary files.')));
    });

    test('package is under source control and .gitignore exists', () async {
      await d.validPackage.create();
      await d.git(appPath, [d.file('.gitignore', 'ignored')]).create();

      expectSizeValidationError(
          equals('Your package is 100.0 MB. Hosted packages must '
              'be smaller than 100 MB.'));
    });
  });
}
