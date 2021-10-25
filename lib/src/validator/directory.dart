// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;

import '../entrypoint.dart';
import '../io.dart';
import '../validator.dart';

/// A validator that validates a package's top-level directories.
class DirectoryValidator extends Validator {
  DirectoryValidator(Entrypoint entrypoint) : super(entrypoint);

  static final _pluralNames = [
    'benchmarks',
    'docs',
    'examples',
    'tests',
    'tools'
  ];

  @override
  Future validate() {
    return Future.sync(() {
      for (var dir in listDir(entrypoint.root.dir)) {
        if (!dirExists(dir)) continue;

        dir = path.basename(dir);
        if (_pluralNames.contains(dir)) {
          // Cut off the "s"
          var singularName = dir.substring(0, dir.length - 1);
          warnings.add('Rename the top-level "$dir" directory to '
              '"$singularName".\n'
              'The Pub layout convention is to use singular directory '
              'names.\n'
              'Plural names won\'t be correctly identified by Pub and other '
              'tools.');
        }

        if (dir.contains(RegExp(r'^samples?$'))) {
          warnings.add('Rename the top-level "$dir" directory to "example".\n'
              'This allows Pub to find your examples and create "packages" '
              'directories for them.\n');
        }
      }
    });
  }
}
