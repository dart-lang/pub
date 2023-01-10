// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart' hide mapMap;
import 'package:path/path.dart' as p;

import 'entrypoint.dart';
import 'package.dart';
import 'solver.dart';
import 'utils.dart';

/// A holistic view of the entire transitive dependency graph for an entrypoint.
class PackageGraph {
  /// The entrypoint.
  final Entrypoint entrypoint;

  /// The transitive dependencies of the entrypoint (including itself).
  ///
  /// This may not include all transitive dependencies of the entrypoint if the
  /// creator of the package graph knows only a subset of the packages are
  /// relevant in the current context.
  final Map<String, Package> packages;

  /// A map of transitive dependencies for each package.
  Map<String, Set<Package>>? _transitiveDependencies;

  PackageGraph(this.entrypoint, this.packages);

  /// Creates a package graph using the data from [result].
  ///
  /// This is generally faster than loading a package graph from scratch, since
  /// the packages' pubspecs are already fully-parsed.
  factory PackageGraph.fromSolveResult(
    Entrypoint entrypoint,
    SolveResult result,
  ) {
    final packages = {
      for (final id in result.packages)
        id.name: id.name == entrypoint.root.name
            ? entrypoint.root
            : Package(
                result.pubspecs[id.name]!,
                entrypoint.cache.getDirectory(id),
              )
    };

    return PackageGraph(entrypoint, packages);
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
        mapMap<String, Package, String, Iterable<String>>(
          packages,
          value: (_, package) => package.dependencies.keys,
        ),
      );
      _transitiveDependencies =
          mapMap<String, Set<String>, String, Set<Package>>(
        closure,
        value: (depender, names) {
          var set = names.map((name) => packages[name]!).toSet();
          set.add(packages[depender]!);
          return set;
        },
      );
    }
    return _transitiveDependencies![package]!;
  }

  bool _isPackageCached(String package) {
    // The root package is not included in the lock file, so we instead ask
    // the entrypoint.
    // TODO(sigurdm): there should be a way to get the id of any package
    // including the root.
    return p.isWithin(entrypoint.cache.rootDir, packages[package]!.dir);
  }

  /// Returns whether [package] is mutable.
  ///
  /// A package is considered to be mutable if it or any of its dependencies
  /// don't come from a cached source, since the user can change its contents
  /// without modifying the pub cache. Information generated from mutable
  /// packages is generally not safe to cache, since it may change frequently.
  bool isPackageMutable(String package) {
    if (!_isPackageCached(package)) return true;

    return transitiveDependencies(package)
        .any((dep) => !_isPackageCached(dep.name));
  }
}
