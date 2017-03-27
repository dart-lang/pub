// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/strict_dependencies.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator strictDeps(Entrypoint entrypoint) =>
    new StrictDependenciesValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    integration('looks normal', () => expectNoValidationError(strictDeps));

    integration('declares an "import" as a dependency in lib/', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0",
            deps: {"silly_monkey": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0"),
        d.dir('lib', [
          d.file(
              'library.dart',
              r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    integration('declares an "export" as a dependency in lib/', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0",
            deps: {"silly_monkey": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0"),
        d.dir('lib', [
          d.file(
              'library.dart',
              r'''
            export 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    integration('declares an "import" as a dependency in bin/', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0",
            deps: {"silly_monkey": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0"),
        d.dir('bin', [
          d.file(
              'library.dart',
              r'''
            import 'package:silly_monkey/silly_monkey.dart';
          '''),
        ]),
      ]).create();

      expectNoValidationError(strictDeps);
    });

    for (var port in ['import', 'export']) {
      for (var isDev in [false, true]) {
        var deps;
        var devDeps;

        if (isDev) {
          devDeps = {"silly_monkey": "^1.2.3"};
        } else {
          deps = {"silly_monkey": "^1.2.3"};
        }
        for (var devDir in ['benchmark', 'example', 'test', 'tool']) {
          integration(
              'declares an "$port" as a '
              '${isDev ? 'dev ': ''}dependency in $devDir/', () {
            d.dir(appPath, [
              d.libPubspec("test_pkg", "1.0.0",
                  deps: deps, devDeps: devDeps, sdk: ">=1.8.0 <2.0.0"),
              d.dir(devDir, [
                d.file(
                    'library.dart',
                    '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
              ]),
            ]).create();

            expectNoValidationError(strictDeps);
          });
        }
      }
    }

    integration('only uses dart: dependencies (not pub packages)', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'dart:async';
        import 'dart:collection';
        import 'dart:typed_data';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('imports itself', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'package:test_pkg/test_pkg.dart';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('has a relative import', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'some/relative/path.dart';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('has an absolute import', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'file://shared/some/library.dart';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('has a parse error preventing reading directives', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import not_supported_keyword 'dart:async';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('has a top-level Dart file with an invalid dependency', () {
      d
          .file(
              path.join(appPath, 'top_level.dart'),
              r'''
        import 'package:';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });

    integration('has a Dart-like file with an invalid dependency', () {
      d
          .file(
              path.join(appPath, 'lib', 'generator.dart.template'),
              r'''
        import 'package:';
      ''')
          .create();

      expectNoValidationError(strictDeps);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    integration('does not declare an "import" as a dependency', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'package:silly_monkey/silly_monkey.dart';
      ''')
          .create();

      expectValidationWarning(strictDeps);
    });

    integration('does not declare an "export" as a dependency', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        export 'package:silly_monkey/silly_monkey.dart';
      ''')
          .create();

      expectValidationWarning(strictDeps);
    });

    integration('has an invalid URI', () {
      d
          .file(
              path.join(appPath, 'lib', 'library.dart'),
              r'''
        import 'package:/';
      ''')
          .create();

      expectValidationWarning(strictDeps);
    });

    for (var port in ['import', 'export']) {
      for (var codeDir in ['bin', 'lib']) {
        integration('declares an "$port" as a devDependency for $codeDir/', () {
          d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0",
                devDeps: {"silly_monkey": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0"),
            d.dir(codeDir, [
              d.file(
                  'library.dart',
                  '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
            ]),
          ]).create();

          expectValidationWarning(strictDeps);
        });
      }
    }

    for (var port in ['import', 'export']) {
      for (var devDir in ['benchmark', 'example', 'test', 'tool']) {
        integration('does not declare an "$port" as a dependency in $devDir/',
            () {
          d.dir(appPath, [
            d.libPubspec("test_pkg", "1.0.0", sdk: ">=1.8.0 <2.0.0"),
            d.dir(devDir, [
              d.file(
                  'library.dart',
                  '''
            $port 'package:silly_monkey/silly_monkey.dart';
          '''),
            ]),
          ]).create();

          expectValidationWarning(strictDeps);
        });
      }
    }

    group('declares an import with an invalid package URL: ', () {
      integration('"package:"', () {
        d.dir(appPath, [
          d.dir('lib', [
            d.file(
                'library.dart',
                r'''
            import 'package:';
          '''),
          ]),
        ]).create();

        expectValidationWarning(strictDeps);
      });

      integration('"package:silly_monkey"', () {
        d.dir(appPath, [
          d.libPubspec("test_pkg", "1.0.0",
              deps: {"silly_monkey": "^1.2.3"}, sdk: ">=1.8.0 <2.0.0"),
          d.dir('lib', [
            d.file(
                'library.dart',
                r'''
            import 'package:silly_monkey';
          '''),
          ]),
        ]).create();

        expectValidationWarning(strictDeps);
      });

      integration('"package:/"', () {
        d.dir(appPath, [
          d.dir('lib', [
            d.file(
                'library.dart',
                r'''
            import 'package:/';
          '''),
          ]),
        ]).create();

        expectValidationWarning(strictDeps);
      });

      integration('"package:/]"', () {
        d.dir(appPath, [
          d.dir('lib', [
            d.file(
                'library.dart',
                r'''
            import 'package:/]';
          '''),
          ]),
        ]).create();

        expectValidationWarning(strictDeps);
      });
    });
  });
}
