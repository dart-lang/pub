// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';

import 'entrypoint.dart';
import 'lock_file.dart';
import 'package.dart';
import 'solver.dart';
import 'source/cached.dart';

/// A holistic view of the entire transitive dependency graph for an entrypoint.
class PackageGraph {
  /// The entrypoint.
  final Entrypoint entrypoint;

  /// The entrypoint's lockfile.
  ///
  /// This describes the sources and resolved descriptions of everything in
  /// [packages].
  final LockFile lockFile;

  /// The transitive dependencies of the entrypoint (including itself).
  ///
  /// This may not include all transitive dependencies of the entrypoint if the
  /// creator of the package graph knows only a subset of the packages are
  /// relevant in the current context.
  final Map<String, Package> packages;

  /// A map of transitive dependencies for each package.
  Map<String, Set<Package>> _transitiveDependencies;

  PackageGraph(this.entrypoint, this.lockFile, this.packages);

  /// Creates a package graph using the data from [result].
  ///
  /// This is generally faster than loading a package graph from scratch, since
  /// the packages' pubspecs are already fully-parsed.
  factory PackageGraph.fromSolveResult(
      Entrypoint entrypoint, SolveResult result) {
    var packages = Map<String, Package>.fromIterable(result.packages,
        key: (id) => id.name,
        value: (id) {
          if (id.name == entrypoint.root.name) return entrypoint.root;

          return Package(result.pubspecs[id.name],
              entrypoint.cache.source(id.source).getDirectory(id));
        });

    return PackageGraph(entrypoint, result.lockFile, packages);
  }

  /// Returns all transitive dependencies of [package].
  ///
  /// For the entrypoint this returns all packages in [packages], which includes
  /// dev and override. For any other package, it ignores dev and override
  /// dependencies.
  Set<Package> transitiveDependencies(String package) {
    if (package == entrypoint.root.name) return packages.values.toSet();

    if (_transitiveDependencies == null) {
      var closure = transitiveClosure(
          mapMap<String, Package, String, Iterable<String>>(packages,
              value: (_, package) => package.dependencies.keys));
      _transitiveDependencies =
          mapMap<String, Set<String>, String, Set<Package>>(closure,
              value: (depender, names) {
        var set = names.map((name) => packages[name]).toSet();
        set.add(packages[depender]);
        return set;
      });
    }

    return _transitiveDependencies[package];
  }

  /// Returns whether [package] is mutable.
  ///
  /// A package is considered to be mutable if it or any of its dependencies
  /// don't come from a cached source, since the user can change its contents
  /// without modifying the pub cache. Information generated from mutable
  /// packages is generally not safe to cache, since it may change frequently.
  bool isPackageMutable(String package) {
    var id = lockFile.packages[package];
    if (id == null) return true;

    if (entrypoint.cache.source(id.source) is! CachedSource) return true;

    return transitiveDependencies(package).any((dep) {
      var depId = lockFile.packages[dep.name];

      // The entrypoint package doesn't have a lockfile entry. It's always
      // mutable.
      if (depId == null) return true;

      return entrypoint.cache.source(depId.source) is! CachedSource;
    });
  }
}
