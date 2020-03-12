// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/changelog.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator changelog(Entrypoint entrypoint) => ChangelogValidator(entrypoint);

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('has a CHANGELOG that includes the current package version', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.file('CHANGELOG.md', '''
# 1.0.0

* Solves traveling salesman problem in polynomial time.
* Passes Turing test.
'''),
      ]).create();
      expectNoValidationError(changelog);
    });
  });

  group('should consider a package invalid if it', () {
    test('has no CHANGELOG', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
      ]).create();
      expectValidationWarning(changelog);
    });

    test('has has a CHANGELOG not named CHANGELOG.md', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.file('CHANGELOG', '''
# 1.0.0

* Solves traveling salesman problem in polynomial time.
* Passes Turing test.
'''),
      ]).create();
      expectValidationWarning(changelog);
    });

    test('has a CHANGELOG that doesn\'t include the current package version',
        () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.1'),
        d.file('CHANGELOG.md', '''
# 1.0.0

* Solves traveling salesman problem in polynomial time.
* Passes Turing test.
'''),
      ]).create();
      expectValidationWarning(changelog);
    });

    test('has a CHANGELOG with invalid utf-8', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0'),
        d.file('CHANGELOG.md', [192]),
      ]).create();
      expectValidationWarning(changelog);
    });
  });
}
