// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/executable.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator executable() => ExecutableValidator();

void main() {
  setUp(d.validPackage().create);

  group('should consider a package valid if it', () {
    test('has executables that are present', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'executables': {'one': 'one_script', 'two': null}
        }),
        d.dir('bin', [
          d.file('one_script.dart', "main() => print('ok');"),
          d.file('two.dart', "main() => print('ok');")
        ])
      ]).create();
      await expectValidationDeprecated(executable);
    });
  });

  group('should consider a package invalid if it', () {
    test('is missing one or more listed executables', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'executables': {'nope': 'not_there', 'nada': null}
        })
      ]).create();
      await expectValidationDeprecated(executable, warnings: isNotEmpty);
    });

    test('has .gitignored one or more listed executables', () async {
      await d.git(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'executables': {'one': 'one_script', 'two': null}
        }),
        d.dir('bin', [
          d.file('one_script.dart', "main() => print('ok');"),
          d.file('two.dart', "main() => print('ok');")
        ]),
        d.file('.gitignore', 'bin')
      ]).create();
      await expectValidationDeprecated(executable, warnings: isNotEmpty);
    });
  });
}
