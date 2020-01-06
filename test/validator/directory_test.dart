// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/directory.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator directory(Entrypoint entrypoint) => DirectoryValidator(entrypoint);

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(directory));

    test('has a nested directory named "tools"', () async {
      await d.dir(appPath, [
        d.dir('foo', [d.dir('tools')])
      ]).create();
      expectNoValidationError(directory);
    });
  });

  group(
      'should consider a package invalid if it has a top-level directory '
      'named', () {
    setUp(d.validPackage.create);

    var names = [
      'benchmarks',
      'docs',
      'examples',
      'sample',
      'samples',
      'tests',
      'tools'
    ];

    for (var name in names) {
      test('"$name"', () async {
        await d.dir(appPath, [d.dir(name)]).create();
        expectValidationWarning(directory);
      });
    }
  });
}
