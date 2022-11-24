// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../io.dart';
import '../validator.dart';

/// The maximum size of the package to upload (100 MB).
const _maxSize = 100 * 1024 * 1024;

/// A validator that validates that a package isn't too big.
class SizeValidator extends Validator {
  @override
  Future<void> validate() async {
    if (packageSize <= _maxSize) return;
    var sizeInMb = (packageSize / (1 << 20)).toStringAsPrecision(4);
    // Current implementation of Package.listFiles skips hidden files
    var ignoreExists = fileExists(entrypoint.root.path('.gitignore'));

    var error = StringBuffer('Your package is $sizeInMb MB. Hosted '
        'packages must be smaller than 100 MB.');

    if (ignoreExists && !entrypoint.root.inGitRepo) {
      error.write(' Your .gitignore has no effect since your project '
          'does not appear to be in version control.');
    } else if (!ignoreExists && entrypoint.root.inGitRepo) {
      error.write(' Consider adding a .gitignore to avoid including '
          'temporary files.');
    }

    errors.add(error.toString());
  }
}
