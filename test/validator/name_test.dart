// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/name.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator name(Entrypoint entrypoint) => NameValidator(entrypoint);

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(name));

    test('has dots in potential library names', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.dir('lib', [
          d.file('test_pkg.dart', 'int i = 1;'),
          d.file('test_pkg.g.dart', 'int j = 2;')
        ])
      ]).create();
      expectNoValidationError(name);
    });

    test('has a name that starts with an underscore', () async {
      await d.dir(appPath, [
        d.libPubspec('_test_pkg', '1.0.0'),
        d.dir('lib', [d.file('_test_pkg.dart', 'int i = 1;')])
      ]).create();
      expectNoValidationError(name);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    test('has a package name that contains upper-case letters', () async {
      await d.dir(appPath, [d.libPubspec('TestPkg', '1.0.0')]).create();
      expectValidationWarning(name);
    });

    test('has a single library named differently than the package', () async {
      deleteEntry(path.join(d.sandbox, appPath, 'lib', 'test_pkg.dart'));
      await d.dir(appPath, [
        d.dir('lib', [d.file('best_pkg.dart', 'int i = 0;')])
      ]).create();
      expectValidationWarning(name);
    });
  });
}
