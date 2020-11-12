// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../entrypoint.dart';
import '../exceptions.dart';
import '../null_safety_analysis.dart';
import '../package_name.dart';
import '../validator.dart';

/// Gives a warning when publishing a new version, if the latest published
/// version lower to this was not opted into null-safety.
class RelativeVersionNumberingValidator extends Validator {
  static const String semverUrl =
      'https://dart.dev/tools/pub/versioning#semantic-versions';

  final String _server;

  RelativeVersionNumberingValidator(Entrypoint entrypoint, this._server)
      : super(entrypoint);

  @override
  Future<void> validate() async {
    final hostedSource = entrypoint.cache.sources.hosted;
    List<PackageId> existingVersions;
    try {
      existingVersions = await hostedSource
          .bind(entrypoint.cache)
          .getVersions(hostedSource.refFor(entrypoint.root.name, url: _server));
    } on PackageNotFoundException {
      existingVersions = [];
    }
    existingVersions..sort((a, b) => a.version.compareTo(b.version));
    final previousVersion = existingVersions.lastWhere(
        (id) => id.version < entrypoint.root.version,
        orElse: () => null);
    if (previousVersion == null) return;

    final previousPubspec =
        await hostedSource.bind(entrypoint.cache).describe(previousVersion);

    final currentOptedIn =
        entrypoint.root.pubspec.languageVersion.supportsNullSafety;
    final previousOptedIn = previousPubspec.languageVersion.supportsNullSafety;

    if (currentOptedIn && !previousOptedIn) {
      hints.add(
          'You\'re about to publish a package that opts into null safety.\n'
          'The previous version (${previousVersion.version}) isn\'t opted in.\n'
          'See ${NullSafetyAnalysis.guideUrl} for best practices.');
    } else if (!currentOptedIn && previousOptedIn) {
      hints.add(
          'You\'re about to publish a package that doesn\'t opt into null safety,\n'
          'but the previous version (${previousVersion.version}) was opted in.\n'
          'This change is likely to be backwards incompatible.\n'
          'See $semverUrl for information about versioning.');
    }
  }
}
