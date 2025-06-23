// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'entrypoint.dart';
import 'package.dart';
import 'solver.dart';
import 'source/cached.dart';
import 'source/sdk.dart';

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
      for (final package in entrypoint.workspaceRoot.transitiveWorkspace)
        package.name: package,
      for (final id in result.packages.where((p) => !p.isRoot))
        id.name: Package(
          result.pubspecs[id.name]!,
          entrypoint.cache.getDirectory(id),
          [],
        ),
    };

    return PackageGraph(entrypoint, packages);
  }

  /// Returns all transitive dependencies of [package].
  ///
  /// For the entrypoint this returns all packages in [packages], which includes
  /// dev and override. For any other package, it ignores dev and override
  /// dependencies.
  Set<Package> transitiveDependencies(
    String package, {
    required bool followDevDependenciesFromRoot,
  }) {
    final result = <Package>{};

    final stack = [package];
    final visited = <String>{};
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!visited.add(current)) continue;
      final currentPackage = packages[current]!;
      result.add(currentPackage);
      stack.addAll(currentPackage.dependencies.keys);
      if (followDevDependenciesFromRoot && current == package) {
        stack.addAll(currentPackage.devDependencies.keys);
      }
    }
    return result;
  }

  bool _isPackageFromImmutableSource(String package) {
    final id = entrypoint.lockFile.packages[package];
    if (id == null) {
      return false; // This is a root package.
    }
    return id.source is CachedSource || id.source is SdkSource;
  }

  /// Returns whether [package] is mutable.
  ///
  /// A package is considered to be mutable if it or any of its dependencies
  /// don't come from a cached source, since the user can change its contents
  /// without modifying the pub cache. Information generated from mutable
  /// packages is generally not safe to cache, since it may change frequently.
  bool isPackageMutable(String package) {
    if (!_isPackageFromImmutableSource(package)) return true;

    return transitiveDependencies(
      package,
      followDevDependenciesFromRoot: true,
    ).any((dep) => !_isPackageFromImmutableSource(dep.name));
  }
}
