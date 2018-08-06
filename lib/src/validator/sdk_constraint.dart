// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../entrypoint.dart';
import '../sdk.dart';
import '../validator.dart';

/// A validator that validates that a package's SDK constraint doesn't use the
/// "^" syntax.
class SdkConstraintValidator extends Validator {
  SdkConstraintValidator(Entrypoint entrypoint) : super(entrypoint);

  Future validate() async {
    var dartConstraint = entrypoint.root.pubspec.originalDartSdkConstraint;
    if (dartConstraint is VersionRange) {
      if (dartConstraint.toString().startsWith("^")) {
        var dartConstraintWithoutCaret = VersionRange(
            min: dartConstraint.min,
            max: dartConstraint.max,
            includeMin: dartConstraint.includeMin,
            includeMax: dartConstraint.includeMax);
        errors.add(
            "^ version constraints aren't allowed for SDK constraints since "
            "older versions of pub don't support them.\n"
            "Expand it manually instead:\n"
            "\n"
            "environment:\n"
            "  sdk: \"$dartConstraintWithoutCaret\"");
      }

      if (dartConstraint.max == null) {
        errors.add(
            'Published packages should have an upper bound constraint on the '
            'Dart SDK (typically this should restrict to less than the next '
            'major version to guard against breaking changes).\n'
            'See https://www.dartlang.org/tools/pub/pubspec#sdk-constraints for '
            'instructions on setting an sdk version constraint.');
      }
    }

    for (var sdk in sdks.values) {
      if (sdk.identifier == 'dart') continue;
      if (entrypoint.root.pubspec.sdkConstraints.containsKey(sdk.identifier)) {
        validateSdkConstraint(sdk.firstPubVersion,
            "Older versions of pub don't support ${sdk.name} SDK constraints.");
      }
    }
  }
}
