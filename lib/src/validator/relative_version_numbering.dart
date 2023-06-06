// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../package_name.dart';
import '../validator.dart';

/// Gives an info if the version number has skipped since the last released, or
/// if the version is not sequentially following the latest.
///
/// Gives an info when publishing a new version, if the latest published
/// version lower to this was not opted into null-safety.
class RelativeVersionNumberingValidator extends Validator {
  static const String semverUrl =
      'https://dart.dev/tools/pub/versioning#semantic-versions';

  static const String nullSafetyGuideUrl =
      'https://dart.dev/null-safety/migration-guide';

  @override
  Future<void> validate() async {
    final hostedSource = entrypoint.cache.hosted;
    List<PackageId> existingVersions;
    try {
      existingVersions = await entrypoint.cache.getVersions(
        hostedSource.refFor(entrypoint.root.name, url: serverUrl.toString()),
      );
    } on PackageNotFoundException {
      existingVersions = [];
    }
    existingVersions.sort((a, b) => a.version.compareTo(b.version));

    final currentVersion = entrypoint.root.pubspec.version;

    final latestVersion =
        existingVersions.isEmpty ? null : existingVersions.last.version;
    if (latestVersion != null && latestVersion > currentVersion) {
      hints.add('''
The latest published version is $latestVersion.
Your version $currentVersion is earlier than that.''');
    }

    final previousRelease = existingVersions
        .lastWhereOrNull((id) => id.version < entrypoint.root.version);

    if (previousRelease == null) return;

    final previousVersion = previousRelease.version;
    final noPrerelease = Version(
      currentVersion.major,
      currentVersion.minor,
      currentVersion.patch,
    );
    if (noPrerelease != previousVersion.nextMajor &&
        noPrerelease != previousVersion.nextMinor &&
        noPrerelease != previousVersion.nextPatch &&
        currentVersion.withoutBuild() != previousVersion) {
      final hint = '''
The previous version is $previousVersion.

It seems you are not publishing an incremental update.

Consider one of:
''';
      final String suggestion;

      if (previousVersion.major == 0) {
        suggestion = '''
* ${previousVersion.nextMajor} for a first major release.
* ${previousVersion.nextBreaking} for a breaking release.
* ${previousVersion.nextPatch} for a minor release.
''';
      } else {
        suggestion = '''
* ${previousVersion.nextBreaking} for a breaking release.
* ${previousVersion.nextMinor} for a minor release.
* ${previousVersion.nextPatch} for a patch release.''';
      }
      hints.add(hint + suggestion);
    }

    final previousPubspec = await entrypoint.cache.describe(previousRelease);

    final currentOptedIn =
        entrypoint.root.pubspec.languageVersion.supportsNullSafety;
    final previousOptedIn = previousPubspec.languageVersion.supportsNullSafety;

    if (currentOptedIn && !previousOptedIn) {
      hints.add(
          'You\'re about to publish a package that opts into null safety.\n'
          'The previous version ($previousVersion) isn\'t opted in.\n'
          'See $nullSafetyGuideUrl for best practices.');
    } else if (!currentOptedIn && previousOptedIn) {
      hints.add(
          'You\'re about to publish a package that doesn\'t opt into null safety,\n'
          'but the previous version ($previousVersion) was opted in.\n'
          'This change is likely to be backwards incompatible.\n'
          'See $semverUrl for information about versioning.');
    }
  }
}

extension on Version {
  Version withoutBuild() =>
      Version(major, minor, patch, pre: preRelease.join('.'));
}
