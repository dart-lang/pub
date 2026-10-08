// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(Matcher output, int exitCode) async {
  await runPub(
    output: output,
    args: ['publish', '--dry-run'],
    workingDirectory: d.path(appPath),
    exitCode: exitCode,
  );
}

void main() {
  test(
    'Recognizes files that only differ in capitalization.',
    () async {
      await d.validPackage().create();
      await d.dir(appPath, [d.file('Pubspec.yaml')]).create();
      await expectValidation(
        allOf(
          matches(r'Package validation found the following \d* ?errors?:'),
          contains(
            'The file ./pubspec.yaml and ./Pubspec.yaml only differ in capitalization.',
          ),
        ),
        DATA,
      );
    },
    onPlatform: {
      'windows': const Skip('Windows file system is case-insensitive'),
      'mac-os': const Skip('macOS file system is case-insensitive'),
    },
  );

  test('Warns against uppercase Dart file in lib/', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('lib', [d.file('Foo.dart', 'int i = 1;')]),
    ]).create();
    await expectValidation(
      allOf(
        contains('Package validation found the following potential issue:'),
        contains(
          'The file lib/Foo.dart contains upper-case letters.\n'
          '  Try renaming it to use lower-case letters and underscores.',
        ),
        contains('Package has 1 warning.'),
      ),
      DATA,
    );
  });

  test('Warns against uppercase Dart file in bin/', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('bin', [d.file('Bar.dart', 'void main() {}')]),
    ]).create();
    await expectValidation(
      allOf(
        contains('Package validation found the following potential issue:'),
        contains(
          'The file bin/Bar.dart contains upper-case letters.\n'
          '  Try renaming it to use lower-case letters and underscores.',
        ),
        contains('Package has 1 warning.'),
      ),
      DATA,
    );
  });

  test(
    'Warns against uppercase directory name containing Dart file in lib/',
    () async {
      await d.validPackage().create();
      await d.dir(appPath, [
        d.dir('lib', [
          d.dir('Folder', [d.file('foo.dart', 'int i = 1;')]),
        ]),
      ]).create();
      await expectValidation(
        allOf(
          contains('Package validation found the following potential issue:'),
          contains(
            'The file lib/Folder/foo.dart contains upper-case letters.\n'
            '  Try renaming it to use lower-case letters and underscores.',
          ),
          contains('Package has 1 warning.'),
        ),
        DATA,
      );
    },
  );

  test(
    'Allows uppercase characters in non-dart files or other folders',
    () async {
      await d.validPackage().create();
      await d.dir(appPath, [
        d.dir('lib', [d.file('README.txt', 'hello')]),
        d.dir('test', [d.file('Foo_test.dart', 'void main() {}')]),
      ]).create();
      await expectValidation(contains('Package has 0 warnings.'), SUCCESS);
    },
  );
}
