// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import '../http.dart';
import '../lock_file.dart';
import '../log.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source/cached.dart';
import '../system_cache.dart';

/// The result of a successful version resolution.
class SolveResult {
  /// The list of concrete package versions that were selected for each package
  /// reachable from the root.
  final List<PackageId> packages;

  /// Names of all dependency overrides in the workspace.
  final Set<String> _overriddenPackages;

  /// The root package of this resolution.
  final Package _root;

  /// A map from package names to the pubspecs for the versions of those
  /// packages that were installed.
  final Map<String, Pubspec> pubspecs;

  /// The available versions of all selected packages from their source.
  ///
  /// An entry here may not include the full list of versions available if the
  /// given package was locked and did not need to be unlocked during the solve.
  ///
  /// No version list will not contain any retracted package versions.
  final Map<String, List<Version>> availableVersions;

  /// The number of solutions that were attempted before either finding a
  /// successful solution or exhausting all options.
  ///
  /// In other words, one more than the number of times it had to backtrack
  /// because it found an invalid solution.
  final int attemptedSolutions;

  /// The wall clock time the resolution took.
  final Duration resolutionTime;

  /// Downloads all the cached packages selected by this version resolution.
  ///
  /// If some already cached package differs from what is provided by the server
  /// (according to the content-hash) a warning is printed and the package is
  /// redownloaded.
  ///
  /// Returns the [LockFile] representing the packages selected by this version
  /// resolution. Any resolved [PackageId]s will correspond to those in the
  /// cache (and thus to the one provided by the server).
  ///
  /// If there is a mismatch between the previous content-hash from pubspec.lock
  /// and the new one a warning will be printed but the new one will be
  /// returned.
  Future<LockFile> downloadCachedPackages(SystemCache cache) async {
    final resolvedPackageIds = await progress('Downloading packages', () async {
      return await Future.wait(
        packages.map((id) async {
          if (id.source is CachedSource) {
            return await withDependencyType(
                _root.pubspec.dependencyType(id.name), () async {
              return (await cache.downloadPackage(
                id,
              ))
                  .packageId;
            });
          }
          return id;
        }),
      );
    });
    // Invariant: the content-hashes in PUB_CACHE matches those provided by the
    // server.

    // Don't factor in overridden dependencies' SDK constraints, because we'll
    // accept those packages even if their constraints don't match.
    final nonOverrides = pubspecs.values
        .where((pubspec) => !_overriddenPackages.contains(pubspec.name))
        .toList();

    final sdkConstraints = <String, VersionConstraint>{};
    for (var pubspec in nonOverrides) {
      pubspec.sdkConstraints.forEach((identifier, constraint) {
        sdkConstraints[identifier] = constraint.effectiveConstraint
            .intersect(sdkConstraints[identifier] ?? VersionConstraint.any);
      });
    }
    return LockFile(
      resolvedPackageIds,
      sdkConstraints: {
        for (final MapEntry(:key, :value) in sdkConstraints.entries)
          key: SdkConstraint(value),
      },
      mainDependencies: MapKeySet(_root.dependencies),
      devDependencies: MapKeySet(_root.devDependencies),
      overriddenDependencies: _overriddenPackages,
    );
  }

  final LockFile _previousLockFile;

  /// Returns the names of all packages that were changed.
  ///
  /// This includes packages that were added or removed.
  Set<String> get changedPackages {
    final changed = packages
        .where((id) => _previousLockFile.packages[id.name] != id)
        .map((id) => id.name)
        .toSet();

    return changed.union(
      _previousLockFile.packages.keys
          .where((package) => !availableVersions.containsKey(package))
          .toSet(),
    );
  }

  SolveResult(
    this._root,
    this._overriddenPackages,
    this._previousLockFile,
    this.packages,
    this.pubspecs,
    this.availableVersions,
    this.attemptedSolutions,
    this.resolutionTime,
  );

  @override
  String toString() => 'Took $attemptedSolutions tries to resolve to\n'
      '- ${packages.join("\n- ")}';
}
