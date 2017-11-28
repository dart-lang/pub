// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../http.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'type.dart';

/// Maintains a cache of previously-requested version lists.
class SolverCache {
  final SystemCache _cache;

  /// The already-requested cached version lists.
  final _versions = new Map<PackageRef, List<PackageId>>();

  /// The errors from failed version list requests.
  final _versionErrors = new Map<PackageRef, Pair<Object, Chain>>();

  /// The type of version resolution that was run.
  final SolveType _type;

  /// The root package being solved.
  ///
  /// This is used to send metadata about the relationship between the packages
  /// being requested and the root package.
  final Package _root;

  /// The number of times a version list was requested and it wasn't cached and
  /// had to be requested from the source.
  int _versionCacheMisses = 0;

  /// The number of times a version list was requested and the cached version
  /// was returned.
  int _versionCacheHits = 0;

  SolverCache(this._type, this._cache, this._root);

  /// Gets the list of versions for [package].
  ///
  /// Packages are sorted in descending version order with all "stable"
  /// versions (i.e. ones without a prerelease suffix) before pre-release
  /// versions. This ensures that the solver prefers stable packages over
  /// unstable ones.
  Future<List<PackageId>> getVersions(PackageRef package) async {
    if (package.isRoot) {
      throw new StateError("Cannot get versions for root package $package.");
    }

    if (package.isMagic) return [new PackageId.magic(package.name)];

    // See if we have it cached.
    var versions = _versions[package];
    if (versions != null) {
      _versionCacheHits++;
      return versions;
    }

    // See if we cached a failure.
    var error = _versionErrors[package];
    if (error != null) {
      _versionCacheHits++;
      await new Future.error(error.first, error.last);
    }

    _versionCacheMisses++;

    var source = _cache.source(package.source);
    List<PackageId> ids;
    try {
      ids = await withDependencyType(_root.dependencyType(package.name),
          () => source.getVersions(package));
    } catch (error, stackTrace) {
      // If an error occurs, cache that too. We only want to do one request
      // for any given package, successful or not.
      var chain = new Chain.forTrace(stackTrace);
      log.solver("Could not get versions for $package:\n$error\n\n" +
          chain.terse.toString());
      _versionErrors[package] = new Pair(error, chain);
      rethrow;
    }

    // Sort by priority so we try preferred versions first.
    ids.sort((id1, id2) {
      // Reverse the IDs because we want the newest version at the front of the
      // list.
      return _type == SolveType.DOWNGRADE
          ? Version.antiprioritize(id2.version, id1.version)
          : Version.prioritize(id2.version, id1.version);
    });

    ids = ids.toList();
    _versions[package] = ids;
    return ids;
  }

  /// Returns the previously cached list of versions for the package identified
  /// by [package] or returns `null` if not in the cache.
  List<PackageId> getCachedVersions(PackageRef package) => _versions[package];

  /// Returns a user-friendly output string describing metrics of the solve.
  String describeResults() {
    var results = '''- Requested $_versionCacheMisses version lists
- Looked up $_versionCacheHits cached version lists
''';

    // Uncomment this to dump the visited package graph to JSON.
    //results += _debugWritePackageGraph();

    return results;
  }
}
