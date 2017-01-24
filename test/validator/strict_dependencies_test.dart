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
  group('should consider a package valid if', () {
    setUp(d.validPackage.create);

    integration('looks normal', () => expectNoValidationError(strictDeps));

    integration('declares an "import" as a dependency', () {
      d.dir(appPath, [
        d.libPubspec("test_pkg", "1.0.0", deps: {
          "not_declared": "^1.2.3"
        }, sdk: ">=1.8.0 <2.0.0")
      ]).create();
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:not_declared/not_declared.dart';
      ''').create();
      expectNoValidationError(strictDeps);
    });
  });

  group('should consider a package invalid if', () {
    setUp(d.validPackage.create);

    integration('does not declare an "import" as a dependency', () {
      d.file(path.join(appPath, 'lib', 'library.dart'), r'''
        import 'package:not_declared/not_declared.dart';
      ''').create();

      expectValidationWarning(strictDeps);
    });
  });
}
