// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';

import '../validator.dart';

/// Validates that a package files all are unique even after case-normalization.
class FileCaseValidator extends Validator {
  @override
  Future validate() async {
    final lowerCaseToFile = <String, String>{};
    for (final file in files.sorted()) {
      final lowerCase = file.toLowerCase();
      final existing = lowerCaseToFile[lowerCase];
      if (existing != null) {
        errors.add('''
The file $file and $existing only differ in capitalization.

This is not supported across platforms.

Try renaming one of them.
''');
        break;
      }
      lowerCaseToFile[lowerCase] = file;
    }
  }
}
