// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import '../feature.dart';
import '../package_name.dart';
import 'backtracking_solver.dart';
import 'unselected_package_queue.dart';
import 'version_solver.dart';

/// A representation of the version solver's current selected versions.
///
/// This is used to track the joint constraints from the selected packages on
/// other packages, as well as the set of packages that are depended on but have
/// yet to be selected.
///
/// A [VersionSelection] is always internally consistent. That is, all selected
/// packages are compatible with dependencies on those packages, no constraints
/// are empty, and dependencies agree on sources and descriptions. However, the
/// selection itself doesn't ensure this; that's up to the [BacktrackingSolver]
/// that controls it.
class VersionSelection {
  /// The version solver.
  final BacktrackingSolver _solver;

  /// The packages that have been selected, in the order they were selected.
  List<PackageId> get ids => new UnmodifiableListView<PackageId>(_ids);
  final _ids = <PackageId>[];

  /// The new dependencies added by each id in [_ids].
  final _dependenciesForIds = <Set<Dependency>>[];

  /// Tracks all of the dependencies on a given package.
  ///
  /// Each key is a package. Its value is the list of dependencies placed on
  /// that package, in the order that their dependers appear in [ids].
  final _dependencies = new Map<String, List<Dependency>>();

  /// A priority queue of packages that are depended on but have yet to be
  /// selected.
  final UnselectedPackageQueue _unselected;

  /// The next package for which some version should be selected by the solver.
  PackageRef get nextUnselected =>
      _unselected.isEmpty ? null : _unselected.first;

  VersionSelection(BacktrackingSolver solver)
      : _solver = solver,
        _unselected = new UnselectedPackageQueue(solver);

  /// Adds [id] to the selection.
  Future select(PackageId id) async {
    _unselected.remove(id.toRef());
    _ids.add(id);

    _dependenciesForIds
        .add(await _addDependencies(id, await _solver.depsFor(id)));
  }

  /// Adds dependencies from [depender] on [ranges].
  ///
  /// Returns the set of dependencies that have been added due to [depender].
  Future<Set<Dependency>> _addDependencies(
      PackageId depender, Iterable<PackageRange> ranges) async {
    var newDeps = new Set<Dependency>.identity();
    for (var range in ranges) {
      var deps = getDependenciesOn(range.name);

      var id = selected(range.name);
      if (id != null) {
        newDeps.addAll(await _addDependencies(
            id, await _solver.newDepsFor(id, range.features)));
      }

      var dep = new Dependency(depender, range);
      deps.add(dep);
      newDeps.add(dep);

      if (deps.length == 1 && range.name != _solver.root.name) {
        // If this is the first dependency on this package, add it to the
        // unselected queue.
        await _unselected.add(range.toRef());
      }
    }
    return newDeps;
  }

  /// Removes the most recently selected package from the selection.
  Future unselectLast() async {
    var id = _ids.removeLast();
    await _unselected.add(id.toRef());

    var removedDeps = _dependenciesForIds.removeLast();
    for (var dep in removedDeps) {
      var deps = getDependenciesOn(dep.dep.name);
      while (deps.isNotEmpty && removedDeps.contains(deps.last)) {
        deps.removeLast();
      }

      if (deps.isEmpty) _unselected.remove(dep.dep.toRef());
    }
  }

  /// Returns the selected id for [packageName].
  PackageId selected(String packageName) =>
      ids.firstWhere((id) => id.name == packageName, orElse: () => null);

  /// Gets a "required" reference to the package [name].
  ///
  /// This is the first non-root dependency on that package. All dependencies
  /// on a package must agree on source and description, except for references
  /// to the root package. This will return a reference to that "canonical"
  /// source and description, or `null` if there is no required reference yet.
  ///
  /// This is required because you may have a circular dependency back onto the
  /// root package. That second dependency won't be a root dependency and it's
  /// *that* one that other dependencies need to agree on. In other words, you
  /// can have a bunch of dependencies back onto the root package as long as
  /// they all agree with each other.
  Dependency getRequiredDependency(String name) {
    return getDependenciesOn(name)
        .firstWhere((dep) => !dep.dep.isRoot, orElse: () => null);
  }

  /// Gets the combined [VersionConstraint] currently placed on package [name].
  VersionConstraint getConstraint(String name) {
    var constraint = getDependenciesOn(name)
        .map((dep) => dep.dep.constraint)
        .fold(VersionConstraint.any, (a, b) => a.intersect(b));

    // The caller should ensure that no version gets added with conflicting
    // constraints.
    assert(!constraint.isEmpty);

    return constraint;
  }

  /// Returns whether the [feature] of [package] is already enabled by an
  /// existing dependency.
  bool isFeatureEnabled(String package, Feature feature) {
    if (feature.onByDefault) {
      var dependencies = getDependenciesOn(package);
      return dependencies.isEmpty ||
          dependencies.any((dep) =>
              dep.dep.features[feature.name] != FeatureDependency.unused);
    } else {
      return getDependenciesOn(package)
          .any((dep) => dep.dep.features[feature.name]?.isEnabled == true);
    }
  }

  /// Returns a string description of the dependencies on [name].
  String describeDependencies(String name) =>
      getDependenciesOn(name).map((dep) => "  $dep").join('\n');

  /// Gets the list of known dependencies on package [name].
  ///
  /// Creates an empty list if needed.
  List<Dependency> getDependenciesOn(String name) =>
      _dependencies.putIfAbsent(name, () => <Dependency>[]);
}
