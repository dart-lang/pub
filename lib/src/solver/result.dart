// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:pub/src/null_safety_analysis.dart';
import 'package:pub_semver/pub_semver.dart';

import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source_registry.dart';
import '../system_cache.dart';
import 'report.dart';
import 'type.dart';

/// The result of a successful version resolution.
class SolveResult {
  /// The list of concrete package versions that were selected for each package
  /// reachable from the root.
  final List<PackageId> packages;

  /// The root package of this resolution.
  final Package root;

  /// A map from package names to the pubspecs for the versions of those
  /// packages that were installed.
  final Map<String, Pubspec> pubspecs;

  /// The available versions of all selected packages from their source.
  ///
  /// An entry here may not include the full list of versions available if the
  /// given package was locked and did not need to be unlocked during the solve.
  final Map<String, List<Version>> availableVersions;

  /// The number of solutions that were attempted before either finding a
  /// successful solution or exhausting all options.
  ///
  /// In other words, one more than the number of times it had to backtrack
  /// because it found an invalid solution.
  final int attemptedSolutions;

  /// The [LockFile] representing the packages selected by this version
  /// resolution.
  LockFile get lockFile {
    // Don't factor in overridden dependencies' SDK constraints, because we'll
    // accept those packages even if their constraints don't match.
    var nonOverrides = pubspecs.values
        .where((pubspec) => !root.dependencyOverrides.containsKey(pubspec.name))
        .toList();

    var sdkConstraints = <String, VersionConstraint>{};
    for (var pubspec in nonOverrides) {
      pubspec.sdkConstraints.forEach((identifier, constraint) {
        sdkConstraints[identifier] = constraint
            .intersect(sdkConstraints[identifier] ?? VersionConstraint.any);
      });
    }

    return LockFile(packages,
        sdkConstraints: sdkConstraints,
        mainDependencies: MapKeySet(root.dependencies),
        devDependencies: MapKeySet(root.devDependencies),
        overriddenDependencies: MapKeySet(root.dependencyOverrides));
  }

  final SourceRegistry _sources;

  final LockFile _previousLockFile;

  /// Returns the names of all packages that were changed.
  ///
  /// This includes packages that were added or removed.
  Set<String> get changedPackages {
    if (packages == null) return null;

    var changed = packages
        .where((id) => _previousLockFile.packages[id.name] != id)
        .map((id) => id.name)
        .toSet();

    return changed.union(_previousLockFile.packages.keys
        .where((package) => !availableVersions.containsKey(package))
        .toSet());
  }

  SolveResult(this._sources, this.root, this._previousLockFile, this.packages,
      this.pubspecs, this.availableVersions, this.attemptedSolutions);

  /// Displays a report of what changes were made to the lockfile.
  ///
  /// [type] is the type of version resolution that was run.
  void showReport(SolveType type) {
    SolveReport(type, _sources, root, _previousLockFile, this).show();
  }

  /// Displays a one-line message summarizing what changes were made (or would
  /// be made) to the lockfile.
  ///
  /// If [type] is `SolveType.UPGRADE` it also shows the number of packages
  /// that are not at the latest available version.
  ///
  /// [type] is the type of version resolution that was run.
  void summarizeChanges(SolveType type, {bool dryRun = false}) {
    final report = SolveReport(type, _sources, root, _previousLockFile, this);
    report.summarize(dryRun: dryRun);
    if (type == SolveType.UPGRADE) {
      report.reportOutdated();
    }
  }

  /// Displays a warning if this is not a fully null-safe resolution.
  Future<void> warnAboutMixedMode(
    SystemCache cache, {
    @required bool dryRun,
  }) async {
    if (pubspecs[root.name].languageVersion.supportsNullSafety) {
      final analysis = await NullSafetyAnalysis(cache)
          .nullSafetyComplianceOfResolution(this);
      if (analysis.compliance == NullSafetyCompliance.mixed) {
        log.warning('''
The package resolution is not fully migrated to null-safety.

${analysis.reason}

Either downgrade your sdk constraint, or invoke dart/flutter with 
`--no-sound-null-safety`.

To learn more about available versions of your dependencies try running
`pub outdated --mode=null-safety`.

See more at ${NullSafetyAnalysis.guideUrl}.
''');
      } else if (analysis.compliance == NullSafetyCompliance.analysisFailed) {
        log.warning('''
Could not decide if this package resolution is fully migrated to null-safety:

${analysis.reason}
''');
      }
    }
  }

  @override
  String toString() => 'Took $attemptedSolutions tries to resolve to\n'
      '- ${packages.join("\n- ")}';
}
