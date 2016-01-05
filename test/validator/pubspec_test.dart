// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator/pubspec.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration('should consider a package valid if it has a pubspec', () {
    d.validPackage.create();

    expectNoValidationError((entrypoint) => new PubspecValidator(entrypoint));
  });

  integration('should consider a package invalid if it has a .gitignored '
      'pubspec', () {
    var repo = d.git(appPath, [d.file(".gitignore", "pubspec.yaml")]);
    d.validPackage.create();
    repo.create();

    expectValidationError((entrypoint) => new PubspecValidator(entrypoint));
  });
}
