// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;

import '../io.dart';
import '../validator.dart';

/// A validator that validates a package's top-level directories.
class DirectoryValidator extends Validator {
  static final _pluralNames = [
    'benchmarks',
    'docs',
    'examples',
    'tests',
    'tools'
  ];

  static String docRef = 'See https://dart.dev/tools/pub/package-layout.';

  @override
  Future<void> validate() async {
    final visited = <String>{};
    for (final file in files) {
      // Find the topmost directory name of [file].
      final dir = path.join(
        entrypoint.rootDir,
        path.split(path.relative(file, from: entrypoint.rootDir)).first,
      );
      if (!visited.add(dir)) continue;
      if (!dirExists(dir)) continue;

      final dirName = path.basename(dir);
      if (_pluralNames.contains(dirName)) {
        // Cut off the "s"
        var singularName = dirName.substring(0, dirName.length - 1);
        warnings.add('Rename the top-level "$dirName" directory to '
            '"$singularName".\n'
            'The Pub layout convention is to use singular directory '
            'names.\n'
            'Plural names won\'t be correctly identified by Pub and other '
            'tools.\n$docRef');
      }

      if (dirName.contains(RegExp(r'^samples?$'))) {
        warnings.add('Rename the top-level "$dirName" directory to "example".\n'
            'This allows Pub to find your examples and create "packages" '
            'directories for them.\n$docRef');
      }
    }
  }
}
