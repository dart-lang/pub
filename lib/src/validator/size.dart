// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../io.dart';
import '../validator.dart';

/// The preferred maximum size of the package to upload (100 MB).
const _maxSize = 100 * 1024 * 1024;

/// A validator that validates that a package isn't too big.
class SizeValidator extends Validator {
  @override
  Future<void> validate() async {
    if (packageSize <= _maxSize) return;
    final sizeInMb = (packageSize / (1 << 20)).toStringAsPrecision(4);
    // Current implementation of Package.listFiles skips hidden files
    final ignoreExists = fileExists(package.path('.gitignore'));

    final hint = StringBuffer('''
Your package is $sizeInMb MB.

Consider the impact large downloads can have on the package consumer.''');

    if (ignoreExists && !package.inGitRepo) {
      hint.write('\nYour .gitignore has no effect since your project '
          'does not appear to be in version control.');
    } else if (!ignoreExists && package.inGitRepo) {
      hint.write('\nConsider adding a .gitignore to avoid including '
          'temporary files.');
    }

    hints.add(hint.toString());
  }
}
