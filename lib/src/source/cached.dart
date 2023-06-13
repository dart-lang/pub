// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../io.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';

/// Base class for a [BoundSource] that installs packages into pub's
/// [SystemCache].
///
/// A source should be cached if it requires network access to retrieve
/// packages or the package needs to be "frozen" at the point in time that it's
/// installed. (For example, Git packages are cached because installing from
/// the same repo over time may yield different commits.)
abstract class CachedSource extends Source {
  /// If [id] is already in the system cache, just loads it from there.
  ///
  /// Otherwise, defers to the subclass.
  @override
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache) async {
    var packageDir = getDirectoryInCache(id, cache);
    if (fileExists(path.join(packageDir, 'pubspec.yaml'))) {
      return Pubspec.load(packageDir, cache.sources, expectedName: id.name);
    }

    return await describeUncached(id, cache);
  }

  @override
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  }) =>
      getDirectoryInCache(id, cache);

  String getDirectoryInCache(PackageId id, SystemCache cache);

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// This will only be called for packages that have not yet been installed in
  /// the system cache.
  Future<Pubspec> describeUncached(PackageId id, SystemCache cache);

  /// Downloads the package identified by [id] to the system cache.
  Future<DownloadPackageResult> downloadToSystemCache(
    PackageId id,
    SystemCache cache,
  );

  /// Returns the [Package]s that have been downloaded to the system cache.
  List<Package> getCachedPackages(SystemCache cache);

  /// Reinstalls all packages that have been previously installed into the
  /// system cache by this source.
  ///
  /// Returns a list of results indicating for each if that package was
  /// successfully repaired.
  Future<Iterable<RepairResult>> repairCachedPackages(SystemCache cache);
}

/// The result of repairing a single cache entry.
class RepairResult {
  /// `true` if [package] was repaired successfully.
  /// `false` if something failed during the repair.
  ///
  /// When something goes wrong the package is attempted removed from
  /// cache (but that might itself have failed).
  final bool success;
  final String packageName;
  final Version version;
  final Source source;
  RepairResult(
    this.packageName,
    this.version,
    this.source, {
    required this.success,
  });
}

class DownloadPackageResult {
  /// The resolved package.
  final PackageId packageId;

  /// Whether we had to make changes in the cache in order to download the
  /// package.
  final bool didUpdate;

  DownloadPackageResult(this.packageId, {required this.didUpdate});
}
