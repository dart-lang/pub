// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('passes if no analysis_options.yaml exists', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation();
  });

  test('passes if analysis_options.yaml has no include', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation();
  });

  test('passes if analysis_options.yaml includes package: URI', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: package:lints/recommended.yaml
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation();
  });

  test(
    'passes if analysis_options.yaml includes a local file inside the package',
    () async {
      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.file('analysis_options.yaml', '''
include: custom_options.yaml
'''),
        d.file('custom_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidation();
    },
  );

  test(
    'passes if subfolder analysis_options.yaml includes root options',
    () async {
      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.file('analysis_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
        d.dir('example', [
          d.file('analysis_options.yaml', '''
include: ../analysis_options.yaml
'''),
        ]),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidation();
    },
  );

  test(
    'warns if analysis_options.yaml includes a file from parent directory',
    () async {
      await d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''').create();

      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.file('analysis_options.yaml', '''
include: ../parent_options.yaml
'''),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidationWarning(
        'The analysis options file `analysis_options.yaml` includes '
        '`../parent_options.yaml`, which points to a file outside the package.',
      );
    },
  );

  test(
    'warns if subfolder analysis_options.yaml includes a file outside package',
    () async {
      await d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''').create();

      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.dir('example', [
          d.file('analysis_options.yaml', '''
include: ../../parent_options.yaml
'''),
        ]),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidationWarning(
        'The analysis options file `example/analysis_options.yaml` includes '
        '`../../parent_options.yaml`, which points to a file outside the package.',
      );
    },
  );

  test('warns if transitive include points outside package', () async {
    await d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''').create();

    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: internal_options.yaml
'''),
      d.file('internal_options.yaml', '''
include: ../parent_options.yaml
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidationWarning(
      'The analysis options file `internal_options.yaml` includes '
      '`../parent_options.yaml`, which points to a file outside the package.',
    );
  });

  test('warns if file: URI points outside package', () async {
    final parentFile = d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''');
    await parentFile.create();

    final parentUri = Uri.file(parentFile.io.path).toString();

    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: $parentUri
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidationWarning(
      'The analysis options file `analysis_options.yaml` includes '
      '`$parentUri`, which points to a file outside the package.',
    );
  });

  test('warns with --directory flag', () async {
    await d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''').create();

    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: ../parent_options.yaml
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation(
      message: allOf([
        contains(
          'The analysis options file `analysis_options.yaml` includes '
          '`../parent_options.yaml`, which points to a file outside the package.',
        ),
        contains('Package has 1 warning.'),
      ]),
      exitCode: DATA,
      extraArgs: ['--directory', appPath],
      workingDirectory: d.sandbox,
    );
  });
}
