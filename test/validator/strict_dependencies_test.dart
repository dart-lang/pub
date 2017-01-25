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

Validator strictDeps(Entrypoint entrypoint) {
  return new StrictDependenciesValidator(entrypoint);
}

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    integration('looks normal', () => expectNoValidationError(strictDeps));

    integration('declares an "import" as a dependency', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", deps: {
          "silly_monkey": "^1.2.3"
        }, sdk: ">=1.8.0 <2.0.0"),
        d.file(path.join('lib', 'library.dart'), r'''
          import 'package:silly_monkey/silly_monkey.dart';
        '''),
      ]).create();
      expectNoValidationError(strictDeps);
    });

    integration('declares an "import" as a dev dependency', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", devDeps: {
          "silly_monkey": "^1.2.3"
        }, sdk: ">=1.8.0 <2.0.0"),
        d.file(path.join('lib', 'library.dart'), r'''
          import 'package:silly_monkey/silly_monkey.dart';
        '''),
      ]).create();
      expectNoValidationError(strictDeps);
    });

    integration('only uses dart: dependencies (not pub packages)', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'dart:async';
        import 'dart:collection';
        import 'dart:typed_data';
      ''').create();
      expectNoValidationError(strictDeps);
    });

    integration('imports itself', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:test_pkg/test_pkg.dart';
      ''').create();
      expectNoValidationError(strictDeps);
    });

    integration('has a relative import', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'some/relative/path.dart';
      ''').create();
      expectNoValidationError(strictDeps);
    });

    integration('has an absolute import', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'file://shared/some/library.dart';
      ''').create();
      expectNoValidationError(strictDeps);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    integration('does not declare an "import" as a dependency', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      expectValidationWarning(strictDeps);
    });

    integration('has a parse error preventing reading directives', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import not_supported_keyword 'dart:async';
      ''').create();

      expectValidationWarning(strictDeps);
    });

    integration('does not declare an "export" as a dependency', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        export 'package:silly_monkey/silly_monkey.dart';
      ''').create();

      expectValidationWarning(strictDeps);
    });
  });
}
