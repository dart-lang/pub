// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../entrypoint.dart';
import '../exceptions.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../validator.dart';

/// Gives a warning when publishing a new version, if the latest published version
/// was not opted into null-safety.
class RelativeVersionNumberingValidator extends Validator {
  static const String guideUrl =
      'http://dart.dev/null-safety-package-migration-guide';
  final String _server;

  RelativeVersionNumberingValidator(Entrypoint entrypoint, this._server)
      : super(entrypoint);

  @override
  Future<void> validate() async {
    final packageSdkMinVersion = _sdkLowerConstraint(entrypoint.root.pubspec);
    if (packageSdkMinVersion == null ||
        packageSdkMinVersion < _firstVersionSupportingNullSafety) return;

    final hostedSource = entrypoint.cache.sources.hosted;
    List<PackageId> existingVersions;
    try {
      existingVersions = await hostedSource
          .bind(entrypoint.cache)
          .getVersions(hostedSource.refFor(entrypoint.root.name, url: _server));
    } on PackageNotFoundException {
      existingVersions = [];
    }
    if (existingVersions.isEmpty) return; // TODO(sigurdm): is this right?
    existingVersions..sort((a, b) => a.version.compareTo(b.version));
    final latestVersion = existingVersions.last;
    final latestPubspec =
        await hostedSource.bind(entrypoint.cache).describe(latestVersion);
    final latestSdkMinVersion = _sdkLowerConstraint(latestPubspec);
    if (latestSdkMinVersion < _firstVersionSupportingNullSafety) {
      warnings
          .add('You are about to publish a package opting into null-safety.\n'
              'The latest version ${latestVersion.version} has not opted in.\n'
              'Be sure to read $guideUrl for best practices.');
    }
  }

  static Version _sdkLowerConstraint(Pubspec pubspec) {
    final sdkConstraint = pubspec.originalDartSdkConstraint;

    /// If the sdk constraint is not a `VersionRange` something is wrong, and
    /// we cannot deduce the language version.
    ///
    /// This will hopefully be detected elsewhere.
    ///
    /// A single `Version` is also a `VersionRange`.
    if (sdkConstraint is! VersionRange) return null;

    return (sdkConstraint as VersionRange).min;
  }

  static final _firstVersionSupportingNullSafety = Version.parse('2.10.0');
}
