// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dart_apitool/api_tool.dart';
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../validator.dart';

/// A validator that uses `dart_apitool` to check for breaking API changes
/// compared to the previous published version on the package server.
///
/// Emits a warning during `dart pub publish` if breaking changes are detected
/// when publishing a non-breaking version bump (e.g. minor or patch bump).
class ApiBreakageValidator extends Validator {
  @override
  Future<void> validate() async {
    final hostedSource = cache.hosted;
    List<PackageId> existingVersions;
    try {
      existingVersions = await cache.getVersions(
        hostedSource.refFor(package.name, url: serverUrl.toString()),
      );
    } on PackageNotFoundException {
      existingVersions = [];
    }
    existingVersions.sort((a, b) => a.version.compareTo(b.version));

    final currentVersion = package.version;
    final previousRelease = existingVersions.lastWhereOrNull(
      (id) => id.version < currentVersion,
    );

    if (previousRelease == null) return;

    final previousVersion = previousRelease.version;

    // Find the latest stable release before currentVersion to determine if
    // currentVersion represents a breaking release cycle.
    final previousStable = existingVersions.lastWhereOrNull(
      (id) => !id.version.isPreRelease && id.version < currentVersion,
    );

    // If currentVersion is already a breaking SemVer bump relative to the
    // previous stable version (or previous release), breaking changes are
    // expected.
    final baselineForBreakingCheck = previousStable ?? previousRelease;
    if (isBreakingVersionBump(
      baselineForBreakingCheck.version,
      currentVersion,
    )) {
      return;
    }

    try {
      final downloadResult = await cache.downloadPackage(previousRelease);
      final previousDir = cache.getDirectory(downloadResult.packageId);
      final currentDir = package.dir;

      final oldApi =
          await PackageApiAnalyzer(
            packagePath: previousDir,
            doAnalyzePlatformConstraints: false,
          ).analyze();
      final newApi =
          await PackageApiAnalyzer(
            packagePath: currentDir,
            doAnalyzePlatformConstraints: false,
          ).analyze();

      final diffResult = PackageApiDiffer().diff(
        oldApi: oldApi,
        newApi: newApi,
      );

      final breakingChanges =
          diffResult.apiChanges
              .where(
                (change) =>
                    change.isBreaking && change.affectedDeclaration != null,
              )
              .toList();

      if (breakingChanges.isNotEmpty) {
        final buffer = StringBuffer();
        buffer.writeln(
          'Breaking API change(s) detected compared to published version '
          '$previousVersion.\n'
          'Your current version ($currentVersion) is not a breaking SemVer '
          'bump.\n'
          'Suggested version: '
          '${baselineForBreakingCheck.version.nextBreaking}\n'
          'Please bump your version according to Semantic Versioning before '
          'publishing.\n'
          '\nDetected breaking changes:',
        );
        for (final change in breakingChanges) {
          buffer.writeln('  - ${change.changeDescription}');
        }
        warnings.add(buffer.toString().trimRight());
      }
    } catch (error, stackTrace) {
      log.fine('dart_apitool analysis failed:\n$error\n$stackTrace');
    }
  }
}

/// Returns true if [newVersion] is a breaking change version bump over
/// [oldVersion] according to Dart Semantic Versioning rules.
bool isBreakingVersionBump(Version oldVersion, Version newVersion) {
  return newVersion.baseVersion >= oldVersion.nextBreaking;
}

extension on Version {
  Version get baseVersion => Version(major, minor, patch);
}
