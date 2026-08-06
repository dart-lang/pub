// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('ignores a warning using ignored_validations in pubspec.yaml', () async {
    final pkg = d.validPackage(
      pubspecExtras: {
        'ignored_validations': ['readme'],
      },
    );
    await pkg.create();
    deleteEntry(p.join(d.sandbox, 'myapp/README.md'));

    await expectValidation(
      message: allOf([
        contains('Ignored validation issues from: readme.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });

  test('ignores an error using ignored_validations in pubspec.yaml', () async {
    final pkg = d.validPackage(
      pubspecExtras: {
        'ignored_validations': ['license'],
      },
    );
    await pkg.create();
    deleteEntry(p.join(d.sandbox, 'myapp/LICENSE'));

    await expectValidation(
      message: allOf([
        contains('Ignored validation issues from: license.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });

  test('ignores a warning using --ignore-validation CLI flag', () async {
    final pkg = d.validPackage();
    await pkg.create();
    deleteEntry(p.join(d.sandbox, 'myapp/README.md'));

    await expectValidation(
      extraArgs: ['--ignore-validation=readme'],
      message: allOf([
        contains('Ignored validation issues from: readme.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });

  test('ignores an error using --ignore-validation CLI flag', () async {
    final pkg = d.validPackage();
    await pkg.create();
    deleteEntry(p.join(d.sandbox, 'myapp/LICENSE'));

    await expectValidation(
      extraArgs: ['--ignore-validation=license'],
      message: allOf([
        contains('Ignored validation issues from: license.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });

  test(
    'warns if ignored_validations entry in pubspec.yaml was unnecessary',
    () async {
      final pkg = d.validPackage(
        pubspecExtras: {
          'ignored_validations': ['readme'],
        },
      );
      await pkg.create();

      await expectValidationWarning(
        'Validation "readme" was ignored in pubspec.yaml, but produced no '
        'warnings or errors. Consider removing it from "ignored_validations".',
      );
    },
  );

  test('does not warn for unnecessary CLI --ignore-validation flag', () async {
    final pkg = d.validPackage();
    await pkg.create();

    await expectValidation(
      extraArgs: ['--ignore-validation=readme'],
      message: contains('Package has 0 warnings.'),
    );
  });

  test('fails if unrecognized validator name is in pubspec.yaml', () async {
    final pkg = d.validPackage(
      pubspecExtras: {
        'ignored_validations': ['not_a_validator'],
      },
    );
    await pkg.create();

    await runPub(
      args: ['publish', '--dry-run'],
      error: contains(
        'Unrecognized validator name "not_a_validator" in '
        '"ignored_validations".',
      ),
      exitCode: DATA,
    );
  });

  test('fails if ignored_validations is not a list in pubspec.yaml', () async {
    final pkg = d.validPackage(
      pubspecExtras: {'ignored_validations': 'not_a_list'},
    );
    await pkg.create();

    await runPub(
      args: ['publish', '--dry-run'],
      error: contains(
        '"ignored_validations" field must be a list of validator names',
      ),
      exitCode: DATA,
    );
  });

  test(
    'fails if unrecognized validator name is passed to --ignore-validation',
    () async {
      final pkg = d.validPackage();
      await pkg.create();

      await runPub(
        args: ['publish', '--dry-run', '--ignore-validation=not_a_validator'],
        error: contains(
          'Unrecognized validator name "not_a_validator" passed to '
          '`--ignore-validation`.',
        ),
        exitCode: USAGE,
      );
    },
  );

  test('combines ignored validations from pubspec.yaml and CLI', () async {
    final pkg = d.validPackage(
      pubspecExtras: {
        'ignored_validations': ['readme'],
      },
    );
    await pkg.create();
    deleteEntry(p.join(d.sandbox, 'myapp/README.md'));
    deleteEntry(p.join(d.sandbox, 'myapp/LICENSE'));

    await expectValidation(
      extraArgs: ['--ignore-validation=license'],
      message: allOf([
        contains('Ignored validation issues from: license, readme.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });

  test('ignores pubspec_exists and package_layout validations', () async {
    final pkg = d.validPackage(
      pubspecExtras: {
        'ignored_validations': ['package_layout'],
      },
    );
    await pkg.create();
    await d.dir(appPath, [
      d.dir('examples', [d.file('example.dart', 'void main() {}')]),
    ]).create();

    await expectValidation(
      message: allOf([
        contains('Ignored validation issues from: package_layout.'),
        contains('Package has 0 warnings.'),
      ]),
    );
  });
}
