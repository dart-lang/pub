// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as path;

import '../entrypoint.dart';
import '../io.dart';
import '../validator.dart';


/// A validator that validates a package's changelog file.
class ChangelogValidator extends Validator {
  ChangelogValidator(Entrypoint entrypoint) : super(entrypoint);

  Future validate() {
    return Future.sync(() {
      final changelog = entrypoint.root.changelogPath;

      if (changelog == null) {
        // No changelog was found, which is fine. Return with no warnings.
        return;
      }

      var bytes = readBinaryFile(changelog);
      var contents = '';

      try {
        // utf8.decode doesn't allow invalid UTF-8.
        contents = utf8.decode(bytes);
      } on FormatException catch (_) {
        warnings.add("$changelog contains invalid UTF-8.\n"
            "This will cause it to be displayed incorrectly on "
            "pub.dartlang.org.");
      }

      final version = entrypoint.root.pubspec.version.toString();

      if (!contents.contains(version)) {
        warnings.add("Your package includes a changelog file that doesn\'t "
            "mention version $version. Consider updating it prior to "
            "publication.");
      }
    });
  }
}
