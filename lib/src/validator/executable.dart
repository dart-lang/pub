// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../validator.dart';

/// Validates that a package's pubspec doesn't contain executables that
/// reference non-existent scripts.
class ExecutableValidator extends Validator {
  @override
  Future validate() async {
    final binFiles =
        filesBeneath('bin', recursive: false).map(entrypoint.root.relative);

    entrypoint.root.pubspec.executables.forEach((executable, script) {
      var scriptPath = p.join('bin', '$script.dart');
      if (binFiles.contains(scriptPath)) return;

      warnings.add('Your pubspec.yaml lists an executable "$executable" that '
          'points to a script "$scriptPath" that does not exist.');
    });
  }
}
