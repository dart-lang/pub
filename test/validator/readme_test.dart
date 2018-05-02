// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/readme.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator readme(Entrypoint entrypoint) => new ReadmeValidator(entrypoint);

main() {
  setUp(d.validPackage.create);

  group('should consider a package valid if it', () {
    test('looks normal', () => expectNoValidationError(readme));

    test('has a non-primary readme', () async {
      deleteEntry(p.join(d.sandbox, "myapp/README.md"));

      await d.dir(appPath, [d.file("README.whatever")]).create();
      expectNoValidationError(readme);
    });

    test('has a non-primary readme with invalid utf-8', () async {
      await d.dir(appPath, [
        d.file("README.x.y.z", [192])
      ]).create();
      expectNoValidationError(readme);
    });

    test('has a gitignored README with invalid utf-8', () async {
      var repo = d.git(appPath, [
        d.file("README", [192]),
        d.file(".gitignore", "README")
      ]);
      await repo.create();
      expectNoValidationError(readme);
    });
  });

  group('should consider a package invalid if it', () {
    test('has no README', () {
      deleteEntry(p.join(d.sandbox, "myapp/README.md"));
      expectValidationWarning(readme);
    });

    test('has only a .gitignored README', () async {
      await d.git(appPath, [d.file(".gitignore", "README.md")]).create();
      expectValidationWarning(readme);
    });

    test('has a primary README with invalid utf-8', () async {
      await d.dir(appPath, [
        d.file("README", [192])
      ]).create();
      expectValidationWarning(readme);
    });
  });
}
