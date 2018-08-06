// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that checks that a LICENSE-like file exists.
class LicenseValidator extends Validator {
  LicenseValidator(Entrypoint entrypoint) : super(entrypoint);

  Future validate() {
    return Future.sync(() {
      var licenseLike =
          RegExp(r"^(([a-zA-Z0-9]+[-_])?(LICENSE|COPYING)|UNLICENSE)(\..*)?$");
      if (entrypoint.root
          .listFiles(recursive: false, useGitIgnore: true)
          .map(path.basename)
          .any(licenseLike.hasMatch)) {
        return;
      }

      errors.add(
          "You must have a COPYING, LICENSE or UNLICENSE file in the root directory.\n"
          "An open-source license helps ensure people can legally use your "
          "code.");
    });
  }
}
