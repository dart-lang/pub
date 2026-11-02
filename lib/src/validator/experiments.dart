// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../validator.dart';

/// A validator that checks that packages enabling experiments are published as
/// pre-release versions (and, when enabling SDK experiments, have a pre-release
/// SDK constraint).
class ExperimentsValidator extends Validator {
  @override
  Future<void> validate() async {
    final enabledExperiments = package.pubspec.experiments;
    if (enabledExperiments.isEmpty) return;

    if (!package.version.isPreRelease) {
      errors.add(
        'Packages that enable experiments must be published as a pre-release '
        'version (for example, "${package.version}-0").\n'
        'See https://dart.dev/tools/pub/publishing#publishing-prereleases '
        'for more information on pre-releases.',
      );
    }

    final hasSdkExperiments = enabledExperiments.any((e) => !e.contains('.'));
    if (hasSdkExperiments) {
      final dartConstraint =
          package.pubspec.dartSdkConstraint.originalConstraint;
      final dartMin =
          dartConstraint is VersionRange ? dartConstraint.min : null;
      final flutterConstraint =
          package.pubspec.sdkConstraints['flutter']?.originalConstraint;
      final flutterMin =
          flutterConstraint is VersionRange ? flutterConstraint.min : null;
      final hasPreReleaseSdkConstraint =
          (dartMin != null && dartMin.isPreRelease) ||
          (flutterMin != null && flutterMin.isPreRelease);

      if (!hasPreReleaseSdkConstraint) {
        errors.add(
          'Packages that enable SDK experiments must have a pre-release SDK '
          'constraint (for example, `sdk: ^3.8.0-0`).',
        );
      }
    }
  }
}
