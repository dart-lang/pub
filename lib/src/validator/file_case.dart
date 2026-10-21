// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';

import '../path.dart';
import '../validator.dart';

/// Validates that all files in a package are unique even after
/// case-normalization, and that Dart files in `lib/` and `bin/` do not contain
/// upper-case letters.
final class FileCaseValidator extends Validator {
  static final _upperCase = RegExp(r'[A-Z]');

  @override
  Future<void> validate() async {
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

    final dartFiles =
        [
          ...filesBeneath('lib', recursive: true),
          ...filesBeneath('bin', recursive: true),
        ].where((file) => file.endsWith('.dart')).sorted();

    for (final file in dartFiles) {
      final relative = p.posix.joinAll(
        p.split(p.relative(file, from: package.dir)),
      );
      if (_upperCase.hasMatch(relative)) {
        warnings.add(
          'The file $relative contains upper-case letters.\n'
          'Try renaming it to use lower-case letters and underscores.',
        );
      }
    }
  }
}
