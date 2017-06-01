// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/utf8_readme.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator utf8Readme(Entrypoint entrypoint) =>
    new Utf8ReadmeValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(utf8Readme));

    test('has a non-primary readme with invalid utf-8', () async {
      await d.dir(appPath, [
        d.file("README", "Valid utf-8"),
        d.file("README.invalid", [192])
      ]).create();
      expectNoValidationError(utf8Readme);
    });

    test('has a .gitignored README with invalid utf-8', () async {
      var repo = d.git(appPath, [
        d.file("README", [192]),
        d.file(".gitignore", "README")
      ]);
      await d.validPackage.create();
      await repo.create();
      expectNoValidationError(utf8Readme);
    });
  });

  test(
      'should consider a package invalid if it has a README with '
      'invalid utf-8', () async {
    await d.validPackage.create();

    await d.dir(appPath, [
      d.file("README", [192])
    ]).create();
    expectValidationWarning(utf8Readme);
  });
}
