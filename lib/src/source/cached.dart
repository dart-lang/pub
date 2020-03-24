// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../io.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';

/// Base class for a [BoundSource] that installs packages into pub's
/// [SystemCache].
///
/// A source should be cached if it requires network access to retrieve
/// packages or the package needs to be "frozen" at the point in time that it's
/// installed. (For example, Git packages are cached because installing from
/// the same repo over time may yield different commits.)
abstract class CachedSource extends BoundSource {
  /// The root directory of this source's cache within the system cache.
  ///
  /// This shouldn't be overridden by subclasses.
  String get systemCacheRoot => path.join(systemCache.rootDir, source.name);

  /// If [id] is already in the system cache, just loads it from there.
  ///
  /// Otherwise, defers to the subclass.
  @override
  Future<Pubspec> doDescribe(PackageId id) async {
    var packageDir = getDirectory(id);
    if (fileExists(path.join(packageDir, 'pubspec.yaml'))) {
      return Pubspec.load(packageDir, systemCache.sources,
          expectedName: id.name);
    }

    return await describeUncached(id);
  }

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// This will only be called for packages that have not yet been installed in
  /// the system cache.
  Future<Pubspec> describeUncached(PackageId id);

  @override
  Future get(PackageId id, String symlink) {
    return downloadToSystemCache(id).then((pkg) {
      createPackageSymlink(id.name, pkg.dir, symlink);
    });
  }

  /// Determines if the package identified by [id] is already downloaded to the
  /// system cache.
  bool isInSystemCache(PackageId id) => dirExists(getDirectory(id));

  /// Downloads the package identified by [id] to the system cache.
  Future<Package> downloadToSystemCache(PackageId id);

  /// Returns the [Package]s that have been downloaded to the system cache.
  List<Package> getCachedPackages();

  /// Reinstalls all packages that have been previously installed into the
  /// system cache by this source.
  ///
  /// Returns a list of results indicating for each if that package was
  /// successfully repaired.
  Future<Iterable<RepairResult>> repairCachedPackages();
}

/// The result of repairing a single cache entry.
class RepairResult {
  /// `true` if [package] was repaired successfully.
  /// `false` if something failed during the repair.
  ///
  /// When something goes wrong the package is attempted removed from
  /// cache (but that might itself have failed).
  final bool success;
  final PackageId package;
  RepairResult(this.package, {@required this.success});
}
