// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:path/path.dart' as path;
import 'package:pub/src/path.dart';
import 'package:pub/src/validator/analysis_options.dart';
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

  test('passes if analysis_options.yaml is excluded by .pubignore', () async {
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
      d.file('.pubignore', 'analysis_options.yaml\n'),
      d.file('analysis_options.yaml', '''
include: ../parent_options.yaml
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation();
  });

  test('passes on cyclic includes inside the package', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: other_options.yaml
'''),
      d.file('other_options.yaml', '''
include: analysis_options.yaml
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidation();
  });

  test(
    'hints if analysis_options.yaml includes a file from parent directory',
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

      await expectValidationHint(
        'The analysis options file `analysis_options.yaml` includes '
        '`../parent_options.yaml`, which points to a file outside the package.',
      );
    },
  );

  test(
    'hints if analysis_options.yaml includes an external file in a list',
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
include:
  - package:lints/recommended.yaml
  - ../parent_options.yaml
'''),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidationHint(
        'The analysis options file `analysis_options.yaml` includes '
        '`../parent_options.yaml`, which points to a file outside the package.',
      );
    },
  );

  test(
    'hints if subfolder analysis_options.yaml includes a file outside package',
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

      await expectValidationHint(
        'The analysis options file '
        '`${p.join('example', 'analysis_options.yaml')}` includes '
        '`../../parent_options.yaml`, which points to a file outside the '
        'package.',
      );
    },
  );

  test('hints if transitive include points outside package', () async {
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

    await expectValidationHint(
      'The analysis options file `internal_options.yaml` includes '
      '`../parent_options.yaml`, which points to a file outside the package.',
    );
  });

  test(
    'hints if included local file inside package is excluded by .pubignore',
    () async {
      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.file('.pubignore', 'local_options.yaml\n'),
        d.file('analysis_options.yaml', '''
include: local_options.yaml
'''),
        d.file('local_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidationHint(
        'The analysis options file `analysis_options.yaml` includes '
        '`local_options.yaml`, which is not included in the published package.',
      );
    },
  );

  test(
    'hints if relative include escapes package root and re-enters it',
    () async {
      await d.dir(appPath, [
        d.validPubspec(),
        d.file('LICENSE', 'Eh, do what you want.'),
        d.file('README.md', "This package isn't real."),
        d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
        d.file('analysis_options.yaml', '''
include: ../$appPath/custom_options.yaml
'''),
        d.file('custom_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
        d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
      ]).create();

      await expectValidationHint(
        'The analysis options file `analysis_options.yaml` includes '
        '`../$appPath/custom_options.yaml`, which points to a file outside the '
        'package.',
      );
    },
  );

  test('hints if file: URI points outside package', () async {
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

    await expectValidationHint(
      'The analysis options file `analysis_options.yaml` includes '
      '`$parentUri`, which points to a file outside the package.',
    );
  });

  test('hints if absolute path points outside package', () async {
    final parentFile = d.file('parent_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
''');
    await parentFile.create();

    final parentPath = parentFile.io.path;
    final yamlPath = parentPath.replaceAll("'", "''");

    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('analysis_options.yaml', '''
include: '$yamlPath'
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    await expectValidationHint(
      'The analysis options file `analysis_options.yaml` includes '
      '`$parentPath`, which points to a file outside the package.',
    );
  });

  test('hints if absolute path points inside package', () async {
    await d.dir(appPath, [
      d.validPubspec(),
      d.file('LICENSE', 'Eh, do what you want.'),
      d.file('README.md', "This package isn't real."),
      d.file('CHANGELOG.md', '# 1.0.0\nFirst version\n'),
      d.file('custom_options.yaml', '''
linter:
  rules:
    - avoid_empty_else
'''),
      d.dir('lib', [d.file('test_pkg.dart', 'int i = 1;')]),
    ]).create();

    final insidePath = p.join(d.sandbox, appPath, 'custom_options.yaml');
    final yamlPath = insidePath.replaceAll("'", "''");
    await d.dir(appPath, [
      d.file('analysis_options.yaml', '''
include: '$yamlPath'
'''),
    ]).create();

    await expectValidationHint(
      'The analysis options file `analysis_options.yaml` includes '
      '`$insidePath` using an absolute path.',
    );
  });

  test('hints with --directory flag', () async {
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
        contains('Package has 0 warnings and 1 hint.'),
      ]),
      extraArgs: ['--directory', appPath],
      workingDirectory: d.sandbox,
    );
  });

  group('resolveInclude on Windows paths', () {
    final windowsContext = path.Context(
      style: path.Style.windows,
      current: r'C:\repo\pkg',
    );
    final packageDir = windowsContext.canonicalize(r'C:\repo\pkg');
    final fromFile = windowsContext.canonicalize(
      r'C:\repo\pkg\analysis_options.yaml',
    );

    test('detects drive-letter absolute paths outside package', () {
      withPathContext(pathContext: windowsContext, () {
        for (final includeUri in [
          r'C:\repo\parent_options.yaml',
          'C:/repo/parent_options.yaml',
          r'D:\other\options.yaml',
          r'\\server\share\options.yaml',
          'file:///C:/repo/parent_options.yaml',
        ]) {
          final result = AnalysisOptionsValidator.resolveInclude(
            includeUri,
            fromFile: fromFile,
            packageDir: packageDir,
          );
          expect(
            result.kind,
            IncludeResolutionKind.outsidePackage,
            reason: 'Expected outsidePackage for `$includeUri`',
          );
        }
      });
    });

    test('detects drive-letter absolute paths inside package', () {
      withPathContext(pathContext: windowsContext, () {
        for (final includeUri in [
          r'C:\repo\pkg\custom_options.yaml',
          'C:/repo/pkg/custom_options.yaml',
          'file:///C:/repo/pkg/custom_options.yaml',
        ]) {
          final result = AnalysisOptionsValidator.resolveInclude(
            includeUri,
            fromFile: fromFile,
            packageDir: packageDir,
          );
          expect(
            result.kind,
            IncludeResolutionKind.absoluteInPackage,
            reason: 'Expected absoluteInPackage for `$includeUri`',
          );
        }
      });
    });

    test('ignores package: URIs and accepts relative in-package paths', () {
      withPathContext(pathContext: windowsContext, () {
        expect(
          AnalysisOptionsValidator.resolveInclude(
            'package:lints/recommended.yaml',
            fromFile: fromFile,
            packageDir: packageDir,
          ).kind,
          IncludeResolutionKind.ignored,
        );
        expect(
          AnalysisOptionsValidator.resolveInclude(
            'custom_options.yaml',
            fromFile: fromFile,
            packageDir: packageDir,
          ).kind,
          IncludeResolutionKind.relativeInPackage,
        );
        expect(
          AnalysisOptionsValidator.resolveInclude(
            r'..\parent_options.yaml',
            fromFile: fromFile,
            packageDir: packageDir,
          ).kind,
          IncludeResolutionKind.outsidePackage,
        );
      });
    });
  });
}
