// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/license.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator license(Entrypoint entrypoint) => new LicenseValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(license));

    test('has a COPYING file', () async {
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      await d.file(path.join(appPath, 'COPYING'), '').create();
      expectNoValidationError(license);
    });

    test('has an UNLICENSE file', () async {
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      await d.file(path.join(appPath, 'UNLICENSE'), '').create();
      expectNoValidationError(license);
    });

    test('has a prefixed LICENSE file', () async {
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      await d.file(path.join(appPath, 'MIT_LICENSE'), '').create();
      expectNoValidationError(license);
    });

    test('has a suffixed LICENSE file', () async {
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      await d.file(path.join(appPath, 'LICENSE.md'), '').create();
      expectNoValidationError(license);
    });
  });

  group('should consider a package invalid if it', () {
    test('has no LICENSE file', () async {
      await d.validPackage.create();
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      expectValidationError(license);
    });

    test('has a prefixed UNLICENSE file', () async {
      await d.validPackage.create();
      deleteEntry(path.join(d.sandbox, appPath, 'LICENSE'));
      d.file(path.join(appPath, 'MIT_UNLICENSE'), '').create();
      expectValidationError(license);
    });

    test('has a .gitignored LICENSE file', () async {
      var repo = d.git(appPath, [d.file(".gitignore", "LICENSE")]);
      await d.validPackage.create();
      await repo.create();
      expectValidationError(license);
    });
  });
}
