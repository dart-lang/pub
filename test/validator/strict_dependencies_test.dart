// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/strict_dependencies.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator strictDeps() => StrictDependenciesValidator();

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage().create);

    test('looks normal', () => expectValidationDeprecated(strictDeps));

    test('declares an "import" as a dependency in lib/', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('lib', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });

    test('declares an "export" as a dependency in lib/', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('lib', [
          d.file('library.dart', r'''
            export 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });

    // Regression test of https://github.com/dart-lang/pub/issues/4115 .
    test('imports a dev_dependency in bindings_generator/', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          devDeps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('bindings_generator', [
          d.file('library.dart', r'''
            export 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });

    test('declares an "import" as a dependency in bin/', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('bin', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });

    for (var port in ['import', 'export']) {
      for (var isDev in [false, true]) {
        Map<String, String>? deps;
        Map<String, String>? devDeps;

        if (isDev) {
          devDeps = {'silly_monkey': '^1.2.3'};
        } else {
          deps = {'silly_monkey': '^1.2.3'};
        }
        for (var devDir in ['benchmark', 'example', 'test', 'tool']) {
          test('declares an "$port" as a '
              '${isDev ? 'dev ' : ''}dependency in $devDir/', () async {
            await d.dir(appPath, [
              d.libPubspec(
                'test_pkg',
                '1.0.0',
                deps: deps,
                devDeps: devDeps,
                sdk: '>=1.8.0 <2.0.0',
              ),
              d.dir(devDir, [
                d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
              ]),
            ]).create();

            await expectValidationDeprecated(strictDeps);
          });
        }
      }
    }

    test('only uses dart: dependencies (not pub packages)', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'dart:async';
        import 'dart:collection';
        import 'dart:typed_data';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('imports itself', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:test_pkg/test_pkg.dart';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has a relative import', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'some/relative/path.dart';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has an absolute import', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'file://shared/some/library.dart';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has a parse error preventing reading directives', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import not_supported_keyword 'dart:async';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has a top-level Dart file with an invalid dependency', () async {
      await d.file(p.join(appPath, 'top_level.dart'), r'''
        import 'package:';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has a Dart-like file with an invalid dependency', () async {
      await d.file(p.join(appPath, 'lib', 'generator.dart.template'), r'''
        import 'package:';
      ''').create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has analysis_options.yaml that excludes files', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('lib', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
        d.dir('test', [
          d.dir('data', [
            d.dir('mypkg', [
              d.dir('lib', [d.file('dummy.dart', '\n')]),
            ]),
          ]),
        ]),
        d.file('analysis_options.yaml', r'''analyzer:
  exclude:
    - test/data/**
linter:
  rules:
    - avoid_catching_errors
'''),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });

    test('has lib/analysis_options.yaml that excludes files', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          deps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('lib', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
          d.file('analysis_options.yaml', r'''
analyzer:
  exclude:
    - '**'
linter:
  rules:
    - avoid_catching_errors
'''),
        ]),
        d.dir('test', [
          d.dir('data', [
            d.dir('mypkg', [
              d.dir('lib', [d.file('dummy.dart', '\n')]),
            ]),
          ]),
        ]),
      ]).create();

      await expectValidationDeprecated(strictDeps);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage().create);

    test('has an invalid String value', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:$bad';
      ''').create();

      await expectValidationDeprecated(
        strictDeps,
        errors: [matches('Invalid URL.')],
      );
    });

    test('does not declare an "import" as a dependency', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      await expectValidationDeprecated(
        strictDeps,
        errors: [
          matches('does not have silly_monkey in the `dependencies` section'),
        ],
      );
    });

    test('hook does not declare an "import" as a dependency', () async {
      await d.dir(p.join(appPath, 'hook'), [
        d.file('build.dart', r'''
        import 'package:silly_monkey/silly_monkey.dart';
      '''),
      ]).create();

      await expectValidationDeprecated(
        strictDeps,
        errors: [
          matches('does not have silly_monkey in the `dependencies` section'),
        ],
      );
    });

    test('hook declares an import as a devDependency for', () async {
      await d.dir(appPath, [
        d.libPubspec(
          'test_pkg',
          '1.0.0',
          devDeps: {'silly_monkey': '^1.2.3'},
          sdk: '>=1.8.0 <2.0.0',
        ),
        d.dir('hook', [
          d.file('build.dart', r'''
        import 'package:silly_monkey/silly_monkey.dart';
      '''),
        ]),
      ]).create();

      await expectValidationDeprecated(
        strictDeps,
        errors: [
          matches(
            'silly_monkey is in the `dev_dependencies` section of '
            '`pubspec.yaml`',
          ),
        ],
      );
    });

    test('does not declare an "export" as a dependency', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        export 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      await expectValidationDeprecated(
        strictDeps,
        errors: [
          matches('does not have silly_monkey in the `dependencies` section'),
        ],
      );
    });

    test('has an invalid URI', () async {
      await d.file(p.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:/';
      ''').create();

      await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
    });

    for (var port in ['import', 'export']) {
      for (var codeDir in ['bin', 'lib']) {
        test('declares an "$port" as a devDependency for $codeDir/', () async {
          await d.dir(appPath, [
            d.libPubspec(
              'test_pkg',
              '1.0.0',
              devDeps: {'silly_monkey': '^1.2.3'},
              sdk: '>=1.8.0 <2.0.0',
            ),
            d.dir(codeDir, [
              d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
            ]),
          ]).create();

          await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
        });
      }
    }

    for (var port in ['import', 'export']) {
      for (var devDir in ['benchmark', 'test', 'tool']) {
        test(
          'does not declare an "$port" as a dependency in $devDir/',
          () async {
            await d.dir(appPath, [
              d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0 <2.0.0'),
              d.dir(devDir, [
                d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
              ]),
            ]).create();

            await expectValidationDeprecated(
              strictDeps,
              warnings: [
                matches(
                  'does not have silly_monkey in the '
                  '`dependencies` or `dev_dependencies` section',
                ),
              ],
            );
          },
        );
      }
    }

    group('declares an import with an invalid package URL: ', () {
      test('"package:"', () async {
        await d.dir(appPath, [
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:';
          '''),
          ]),
        ]).create();

        await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
      });

      test('"package:silly_monkey"', () async {
        await d.dir(appPath, [
          d.libPubspec(
            'test_pkg',
            '1.0.0',
            deps: {'silly_monkey': '^1.2.3'},
            sdk: '>=1.8.0 <2.0.0',
          ),
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:silly_monkey';
          '''),
          ]),
        ]).create();

        await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
      });

      test('"package:/"', () async {
        await d.dir(appPath, [
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:/';
          '''),
          ]),
        ]).create();

        await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
      });

      test('"package:/]"', () async {
        await d.dir(appPath, [
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:/]';
          '''),
          ]),
        ]).create();

        await expectValidationDeprecated(strictDeps, errors: isNotEmpty);
      });
    });
  });
}
