// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../validator.dart';

/// A validator of the SDK constraint.
///
/// Validates that a package's SDK constraint:
/// * doesn't use the "^" syntax.
/// * has an upper bound.
/// * is not depending on a prerelease, unless the package itself is a
/// prerelease.
class SdkConstraintValidator extends Validator {
  @override
  Future validate() async {
    final dartConstraint = entrypoint.root.pubspec.dartSdkConstraint;
    final originalConstraint = dartConstraint.originalConstraint;
    final effectiveConstraint = dartConstraint.effectiveConstraint;
    if (originalConstraint is VersionRange) {
      if (originalConstraint.max == null) {
        errors.add(
            'Published packages should have an upper bound constraint on the '
            'Dart SDK (typically this should restrict to less than the next '
            'major version to guard against breaking changes).\n'
            'See https://dart.dev/tools/pub/pubspec#sdk-constraints for '
            'instructions on setting an sdk version constraint.');
      }

      final constraintMin = originalConstraint.min;
      final packageVersion = entrypoint.root.version;

      if (constraintMin != null &&
          constraintMin.isPreRelease &&
          !packageVersion.isPreRelease) {
        warnings.add(
            'Packages with an SDK constraint on a pre-release of the Dart SDK '
            'should themselves be published as a pre-release version. '
            'If this package needs Dart version $constraintMin, consider '
            'publishing the package as a pre-release instead.\n'
            'See https://dart.dev/tools/pub/publishing#publishing-prereleases '
            'For more information on pre-releases.');
      }
      if (
          // We only want to give this hint if there was no other problems with
          // the sdk constraint.
          warnings.isEmpty &&
              errors.isEmpty &&
              originalConstraint != effectiveConstraint) {
        hints.add('''
The declared SDK constraint is '$originalConstraint', this is interpreted as '$effectiveConstraint'.

Consider updating the SDK constraint to:

environment:
  sdk: '$effectiveConstraint'
''');
      }
    }
  }
}
