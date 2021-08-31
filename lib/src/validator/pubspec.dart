// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:async';

import 'package:path/path.dart' as p;

import '../entrypoint.dart';
import '../validator.dart';

/// Validates that a package's pubspec exists.
///
/// In most cases this is clearly true, since pub can't run without a pubspec,
/// but it's possible that the pubspec is gitignored.
class PubspecValidator extends Validator {
  PubspecValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() async {
    var files = entrypoint.root.listFiles(recursive: false);
    if (!files.any((file) =>
        p.canonicalize(file) == p.canonicalize(entrypoint.pubspecPath))) {
      errors.add('The pubspec is hidden, probably by .gitignore or pubignore.');
    }
  }
}
