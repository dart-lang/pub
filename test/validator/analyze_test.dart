// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('should consider a package valid if it contains no warnings or errors',
      () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')])
    ]).create();
    await expectValidation();
  });

  test('should handle having no code in the analyzed directories', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
    ]).create();

    await expectValidation();
  });

  test(
      'follows analysis_options.yaml and should warn if package contains errors in pubspec.yaml',
      () async {
    await d.dir(appPath, [
      d.libPubspec(
        'test_pkg', '1.0.0',
        sdk: '^3.0.0',
        // Using http where https is recommended.
        extras: {'repository': 'http://repo.org/'},
      ),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
linter:
  rules:
    - secure_pubspec_urls
''')
    ]).create();

    await expectValidation(
      error: allOf([
        contains(
          "The 'http' protocol shouldn't be used because it isn't secure. Try using a secure protocol, such as 'https'.",
        ),
        contains('Package has 1 warning.'),
      ]),
      exitCode: DATA,
    );
  });

  test(
      'should consider a package valid even if it contains errors in the example/ sub-folder',
      () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      d.dir('example', [
        d.file('test_pkg.dart', '''
void main() {
  final a = 10; // Unused.
}
''')
      ])
    ]).create();

    await expectValidation();
  });

  test(
      'should warn if package contains errors in bin/, and works with --directory',
      () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      d.dir('bin', [
        d.file('test_pkg.dart', '''
void main() {
// Missing }
''')
      ])
    ]).create();

    await expectValidation(
      error: allOf([
        contains('`dart analyze` found the following issue(s):'),
        contains('Analyzing lib, bin, pubspec.yaml...'),
        contains('error -'),
        contains("Expected to find '}'."),
        contains('Package has 1 warning.')
      ]),
      exitCode: DATA,
      extraArgs: ['--directory', appPath],
      workingDirectory: d.sandbox,
    );
  });

  test('should warn if package contains warnings in test folder', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      d.dir('test', [
        d.file('test_pkg.dart', '''
void main() {
  final a = 10; // Unused.
}
''')
      ]),
    ]).create();

    await expectValidation(
      error: allOf([
        contains('`dart analyze` found the following issue(s):'),
        contains('Analyzing lib, test, pubspec.yaml...'),
        contains('warning -'),
        contains("The value of the local variable 'a' isn't used"),
        contains('Package has 1 warning.')
      ]),
      exitCode: DATA,
    );
  });
}
