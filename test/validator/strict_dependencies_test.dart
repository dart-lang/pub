// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/strict_dependencies.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator strictDeps(Entrypoint entrypoint) =>
    StrictDependenciesValidator(entrypoint);

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(strictDeps));

    test('declares an "import" as a dependency in lib/', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0',
            deps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
        d.dir('lib', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    test('declares an "export" as a dependency in lib/', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0',
            deps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
        d.dir('lib', [
          d.file('library.dart', r'''
            export 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    test('declares an "import" as a dependency in bin/', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0',
            deps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
        d.dir('bin', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    for (var port in ['import', 'export']) {
      for (var isDev in [false, true]) {
        Map<String, String> deps;
        Map<String, String> devDeps;

        if (isDev) {
          devDeps = {'silly_monkey': '^1.2.3'};
        } else {
          deps = {'silly_monkey': '^1.2.3'};
        }
        for (var devDir in ['benchmark', 'example', 'test', 'tool']) {
          test(
              'declares an "$port" as a '
              '${isDev ? 'dev ' : ''}dependency in $devDir/', () async {
            await d.dir(appPath, [
              d.libPubspec('test_pkg', '1.0.0',
                  deps: deps, devDeps: devDeps, sdk: '>=1.8.0 <2.0.0'),
              d.dir(devDir, [
                d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
              ]),
            ]).create();

            expectNoValidationError(strictDeps);
          });
        }
      }
    }

    test('only uses dart: dependencies (not pub packages)', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'dart:async';
        import 'dart:collection';
        import 'dart:typed_data';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('imports itself', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:test_pkg/test_pkg.dart';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has a relative import', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'some/relative/path.dart';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has an absolute import', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'file://shared/some/library.dart';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has a parse error preventing reading directives', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import not_supported_keyword 'dart:async';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has a top-level Dart file with an invalid dependency', () async {
      await d.file(path.join(appPath, 'top_level.dart'), r'''
        import 'package:';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has a Dart-like file with an invalid dependency', () async {
      await d.file(path.join(appPath, 'lib', 'generator.dart.template'), r'''
        import 'package:';
      ''').create();

      expectNoValidationError(strictDeps);
    });

    test('has analysis_options.yaml that excludes files', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0',
            deps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
        d.dir('lib', [
          d.file('library.dart', r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
        d.dir('test', [
          d.dir('data', [
            d.dir('mypkg', [
              d.dir('lib', [
                d.file('dummy.dart', '\n'),
              ]),
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

      expectNoValidationError(strictDeps);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    test('does not declare an "import" as a dependency', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      expectValidationError(strictDeps);
    });

    test('does not declare an "export" as a dependency', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        export 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      expectValidationError(strictDeps);
    });

    test('has an invalid URI', () async {
      await d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:/';
      ''').create();

      expectValidationError(strictDeps);
    });

    for (var port in ['import', 'export']) {
      for (var codeDir in ['bin', 'lib']) {
        test('declares an "$port" as a devDependency for $codeDir/', () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0',
                devDeps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
            d.dir(codeDir, [
              d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
            ]),
          ]).create();

          expectValidationError(strictDeps);
        });
      }
    }

    for (var port in ['import', 'export']) {
      for (var devDir in ['benchmark', 'test', 'tool']) {
        test('does not declare an "$port" as a dependency in $devDir/',
            () async {
          await d.dir(appPath, [
            d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0 <2.0.0'),
            d.dir(devDir, [
              d.file('library.dart', '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
            ]),
          ]).create();

          expectValidationWarning(strictDeps);
        });
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

        expectValidationError(strictDeps);
      });

      test('"package:silly_monkey"', () async {
        await d.dir(appPath, [
          d.libPubspec('test_pkg', '1.0.0',
              deps: {'silly_monkey': '^1.2.3'}, sdk: '>=1.8.0 <2.0.0'),
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:silly_monkey';
          '''),
          ]),
        ]).create();

        expectValidationError(strictDeps);
      });

      test('"package:/"', () async {
        await d.dir(appPath, [
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:/';
          '''),
          ]),
        ]).create();

        expectValidationError(strictDeps);
      });

      test('"package:/]"', () async {
        await d.dir(appPath, [
          d.dir('lib', [
            d.file('library.dart', r'''
            import 'package:/]';
          '''),
          ]),
        ]).create();

        expectValidationError(strictDeps);
      });
    });
  });
}
