// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/directory.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator directory() => DirectoryValidator();

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage().create);

    test('looks normal', () => expectValidationDeprecated(directory));

    test('has a nested directory named "tools"', () async {
      await d.dir(appPath, [
        d.dir('foo', [
          d.dir('tools', [d.file('empty')])
        ])
      ]).create();
      await expectValidationDeprecated(directory);
    });

    test('is pubignoring the folder', () async {
      await d.dir(appPath, [
        d.file('.pubignore', 'tools/\n'),
        d.dir('foo', [
          d.dir('tools', [d.file('empty')])
        ])
      ]).create();
      await expectValidationDeprecated(directory);
    });
  });

  group(
      'should consider a package invalid if it has a top-level directory '
      'named', () {
    setUp(d.validPackage().create);

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
        await d.dir(appPath, [
          d.dir(name, [d.file('empty')])
        ]).create();
        await expectValidationDeprecated(directory, warnings: isNotEmpty);
      });
    }
  });
}
