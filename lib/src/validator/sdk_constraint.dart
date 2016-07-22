// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../entrypoint.dart';
import '../validator.dart';

/// The range of all Dart SDK versions that don't support Flutter SDK
/// constraints.
final _preFlutterSupport = new VersionConstraint.parse("<1.19.0");

/// A validator that validates that a package's SDK constraint doesn't use the
/// "^" syntax.
class SdkConstraintValidator extends Validator {
  SdkConstraintValidator(Entrypoint entrypoint)
    : super(entrypoint);

  Future validate() async {
    var dartConstraint = entrypoint.root.pubspec.dartSdkConstraint;
    if (dartConstraint.toString().startsWith("^")) {
      errors.add(
          "^ version constraints aren't allowed for SDK constraints since "
            "older versions of pub don't support them.\n"
          "Expand it manually instead:\n"
          "\n"
          "environment:\n"
          "  sdk: \">=${dartConstraint.min} <${dartConstraint.max}\"");
    }

    if (entrypoint.root.pubspec.flutterSdkConstraint != null &&
        dartConstraint.allowsAny(_preFlutterSupport)) {
      var newDartConstraint = dartConstraint.difference(_preFlutterSupport);
      if (newDartConstraint.isEmpty ||
          newDartConstraint ==
              VersionConstraint.any.difference(_preFlutterSupport)) {
        newDartConstraint = new VersionConstraint.parse("<2.0.0")
            .difference(_preFlutterSupport);
      }

      errors.add(
          "Older versions of pub don't support Flutter SDK constraints.\n"
          "Make sure your SDK constraint excludes those old versions:\n"
          "\n"
          "environment:\n"
          "  sdk: \"$newDartConstraint\"");
    }
  }
}
