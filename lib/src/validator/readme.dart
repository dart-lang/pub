// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import '../entrypoint.dart';
import '../io.dart';
import '../validator.dart';

/// Validates that a package's README exists and is valid utf-8.
class ReadmeValidator extends Validator {
  ReadmeValidator(Entrypoint entrypoint) : super(entrypoint);

  Future validate() {
    return Future.sync(() {
      var readme = entrypoint.root.readmePath;
      if (readme == null) {
        warnings
            .add("Please add a README.md file that describes your package.");
        return;
      }

      var bytes = readBinaryFile(readme);
      try {
        // utf8.decode doesn't allow invalid UTF-8.
        utf8.decode(bytes);
      } on FormatException catch (_) {
        warnings.add("$readme contains invalid UTF-8.\n"
            "This will cause it to be displayed incorrectly on "
            "pub.dev.");
      }
    });
  }
}
