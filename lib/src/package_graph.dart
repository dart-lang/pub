// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'entrypoint.dart';
import 'package.dart';
import 'solver.dart';

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
  /// If [package] is a root, this will explore the dev_dependencies of
  /// [package] if [followDevDependenciesFromPackage] is true.
  Set<Package> transitiveDependencies(
    String package, {
    required bool followDevDependenciesFromPackage,
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
      if (followDevDependenciesFromPackage &&
          current == package &&
          entrypoint.workspaceRoot.transitiveWorkspace.any(
            (p) => p.name == current,
          )) {
        stack.addAll(currentPackage.devDependencies.keys);
      }
    }
    return result;
  }
}
