// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A back-tracking depth-first solver.
///
/// Attempts to find the best solution for a root package's transitive
/// dependency graph, where a "solution" is a set of concrete package versions.
/// A valid solution will select concrete versions for every package reached
/// from the root package's dependency graph, and each of those packages will
/// fit the version constraints placed on it.
///
/// The solver builds up a solution incrementally by traversing the dependency
/// graph starting at the root package. When it reaches a new package, it gets
/// the set of versions that meet the current constraint placed on it. It
/// *speculatively* selects one version from that set and adds it to the
/// current solution and then proceeds. If it fully traverses the dependency
/// graph, the solution is valid and it stops.
///
/// If it reaches an error because:
///
/// - A new dependency is placed on a package that's already been selected in
///   the solution and the selected version doesn't match the new constraint.
///
/// - There are no versions available that meet the constraint placed on a
///   package.
///
/// - etc.
///
/// then the current solution is invalid. It will then backtrack to the most
/// recent speculative version choice and try the next one. That becomes the
/// new in-progress solution and it tries to proceed from there. It will keep
/// doing this, traversing and then backtracking when it meets a failure until
/// a valid solution has been found or until all possible options for all
/// speculative choices have been exhausted.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import '../barback.dart' as barback;
import '../exceptions.dart';
import '../feature.dart';
import '../flutter.dart' as flutter;
import '../http.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../sdk.dart' as sdk;
import '../source/unknown.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'version_queue.dart';
import 'version_selection.dart';
import 'version_solver.dart';

/// The top-level solver.
///
/// Keeps track of the current potential solution, and the other possible
/// versions for speculative package selections. Backtracks and advances to the
/// next potential solution in the case of a failure.
class BacktrackingSolver {
  final SolveType type;
  final SystemCache systemCache;
  final Package root;

  /// The lockfile that was present before solving.
  final LockFile lockFile;

  /// A cache of data requested during solving.
  final SolverCache cache;

  /// The set of packages that are being explicitly upgraded.
  ///
  /// The solver will only allow the very latest version for each of these
  /// packages.
  final _forceLatest = new Set<String>();

  /// The set of packages whose dependency is being overridden by the root
  /// package, keyed by the name of the package.
  ///
  /// Any dependency on a package that appears in this map will be overriden
  /// to use the one here.
  final _overrides = new Map<String, PackageRange>();

  /// The package versions currently selected by the solver, along with the
  /// versions which are remaining to be tried.
  ///
  /// Every time a package is encountered when traversing the dependency graph,
  /// the solver must select a version for it, sometimes when multiple versions
  /// are valid. This keeps track of which versions have been selected so far
  /// and which remain to be tried.
  ///
  /// Each entry in the list is a [VersionQueue], which is an ordered queue of
  /// versions to try for a single package. It maintains the currently selected
  /// version for that package. When a new dependency is encountered, a queue
  /// of versions of that dependency is pushed onto the end of the list. A
  /// queue is removed from the list once it's empty, indicating that none of
  /// the versions provided a solution.
  ///
  /// The solver tries versions in depth-first order, so only the last queue in
  /// the list will have items removed from it. When a new constraint is placed
  /// on an already-selected package, and that constraint doesn't match the
  /// selected version, that will cause the current solution to fail and
  /// trigger backtracking.
  final _versions = <VersionQueue>[];

  /// The current set of package versions the solver has selected, along with
  /// metadata about those packages' dependencies.
  ///
  /// This has the same view of the selected versions as [_versions], except for
  /// two differences. First, [_versions] doesn't have an entry for the root
  /// package, since it has only one valid version, but [_selection] does, since
  /// its dependencies are relevant. Second, when backtracking, [_versions]
  /// contains the version that's being backtracked, while [_selection] does
  /// not.
  VersionSelection _selection;

  /// The number of solutions the solver has tried so far.
  var _attemptedSolutions = 1;

  /// A pubspec for pub's implicit dependencies on barback and related packages.
  final Pubspec _implicitPubspec;

  BacktrackingSolver(SolveType type, SystemCache systemCache, Package root,
      this.lockFile, List<String> useLatest)
      : type = type,
        systemCache = systemCache,
        root = root,
        cache = new SolverCache(type, systemCache, root),
        _implicitPubspec = _makeImplicitPubspec(systemCache) {
    _selection = new VersionSelection(this);

    for (var package in useLatest) {
      _forceLatest.add(package);
    }

    for (var override in root.dependencyOverrides) {
      _overrides[override.name] = override;
    }
  }

  /// Creates [_implicitPubspec].
  static Pubspec _makeImplicitPubspec(SystemCache systemCache) {
    var dependencies = <PackageRange>[];
    barback.pubConstraints.forEach((name, constraint) {
      dependencies.add(
          systemCache.sources.hosted.refFor(name).withConstraint(constraint));
    });

    return new Pubspec("pub itself", dependencies: dependencies);
  }

  /// Run the solver.
  ///
  /// Completes with a list of specific package versions if successful or an
  /// error if it failed to find a solution.
  Future<SolveResult> solve() async {
    var stopwatch = new Stopwatch();

    _logParameters();

    // Sort the overrides by package name to make sure they're deterministic.
    var overrides = _overrides.values.toList();
    overrides.sort((a, b) => a.name.compareTo(b.name));

    try {
      stopwatch.start();

      // Pre-cache the root package's known pubspec.
      var rootID = new PackageId.root(root);
      await _selection.select(rootID);

      _checkPubspecMatchesSdkConstraint(root.pubspec);

      logSolve();
      var packages = await _solve();

      var pubspecs = <String, Pubspec>{};
      for (var id in packages) {
        pubspecs[id.name] = await _getPubspec(id);
      }

      return new SolveResult.success(
          systemCache.sources,
          root,
          lockFile,
          packages,
          overrides,
          pubspecs,
          _getAvailableVersions(packages),
          _attemptedSolutions);
    } on SolveFailure catch (error) {
      // Wrap a failure in a result so we can attach some other data.
      return new SolveResult.failure(systemCache.sources, root, lockFile,
          overrides, error, _attemptedSolutions);
    } finally {
      // Gather some solving metrics.
      var buffer = new StringBuffer();
      buffer.writeln('${runtimeType} took ${stopwatch.elapsed} seconds.');
      buffer.writeln('- Tried $_attemptedSolutions solutions');
      buffer.writeln(cache.describeResults());
      log.solver(buffer);
    }
  }

  /// Generates a map containing all of the known available versions for each
  /// package in [packages].
  ///
  /// The version list may not always be complete. If the package is the root
  /// root package, or if it's a package that we didn't unlock while solving
  /// because we weren't trying to upgrade it, we will just know the current
  /// version.
  Map<String, List<Version>> _getAvailableVersions(List<PackageId> packages) {
    var availableVersions = <String, List<Version>>{};
    for (var package in packages) {
      var cached = cache.getCachedVersions(package.toRef());
      // If the version list was never requested, just use the one known
      // version.
      var versions = cached == null
          ? [package.version]
          : cached.map((id) => id.version).toList();

      availableVersions[package.name] = versions;
    }

    return availableVersions;
  }

  /// Gets the version of [package] currently locked in the lock file.
  ///
  /// Returns `null` if it isn't in the lockfile (or has been unlocked).
  PackageId getLocked(String package) {
    if (type == SolveType.GET) return lockFile.packages[package];

    // When downgrading, we don't want to force the latest versions of
    // non-hosted packages, since they don't support multiple versions and thus
    // can't be downgraded.
    if (type == SolveType.DOWNGRADE) {
      var locked = lockFile.packages[package];
      if (locked != null && !locked.source.hasMultipleVersions) return locked;
    }

    if (_forceLatest.isEmpty || _forceLatest.contains(package)) return null;
    return lockFile.packages[package];
  }

  /// Gets the package [name] that's currently contained in the lockfile if it
  /// matches the current constraint and has the same source and description as
  /// other references to that package.
  ///
  /// Returns `null` otherwise.
  PackageId _getValidLocked(String name) {
    var package = getLocked(name);
    if (package == null) return null;

    var constraint = _selection.getConstraint(name);
    if (!constraint.allows(package.version)) {
      logSolve('$package is locked but does not match $constraint');
      return null;
    } else {
      logSolve('$package is locked');
    }

    var required = _selection.getRequiredDependency(name);
    if (required != null && !package.samePackage(required.dep)) return null;

    return package;
  }

  /// Tries to find the best set of versions that meet the constraints.
  ///
  /// Selects matching versions of unselected packages, or backtracks if there
  /// are no such versions.
  Future<List<PackageId>> _solve() async {
    // TODO(nweiz): Use real while loops when issue 23394 is fixed.
    await Future.doWhile(() async {
      // Avoid starving the event queue by waiting for a timer-level event.
      await new Future(() {});

      // If there are no more packages to traverse, we've traversed the whole
      // graph.
      var ref = _selection.nextUnselected;
      if (ref == null) return false;

      var queue;
      try {
        queue = await _versionQueueFor(ref);
      } on SolveFailure catch (error) {
        // TODO(nweiz): adjust the priority of [ref] in the unselected queue
        // since we now know it's problematic. We should reselect it as soon as
        // we've selected a different version of one of its dependers.

        // There are no valid versions of [ref] to select, so we have to
        // backtrack and unselect some previously-selected packages.
        if (await _backtrack()) return true;

        // Backtracking failed, which means we're out of possible solutions.
        // Throw the error that caused us to try backtracking.
        if (error is! NoVersionException) rethrow;

        // If we got a NoVersionException, convert it to a
        // non-version-specific one so that it's clear that there aren't *any*
        // acceptable versions that satisfy the constraint.
        throw new NoVersionException(error.package, null,
            (error as NoVersionException).constraint, error.dependencies);
      }

      await _selection.select(queue.current);
      _versions.add(queue);

      logSolve();
      return true;
    });

    // If we got here, we successfully found a solution.
    return _selection.ids.where((id) => !id.isMagic).toList();
  }

  /// Creates a queue of available versions for [ref].
  ///
  /// The returned queue starts at a version that is valid according to the
  /// current dependency constraints. If no such version is available, throws a
  /// [SolveFailure].
  Future<VersionQueue> _versionQueueFor(PackageRef ref) async {
    if (ref.isRoot) {
      return await VersionQueue.create(
          new PackageId.root(root), () => new Future.value([]));
    }

    var locked = _getValidLocked(ref.name);
    var queue = await VersionQueue.create(
        locked, () => _getAllowedVersions(ref, locked));

    await _findValidVersion(queue);

    return queue;
  }

  /// Gets all versions of [ref] that could be selected, other than [locked].
  Future<Iterable<PackageId>> _getAllowedVersions(
      PackageRef ref, PackageId locked) async {
    var allowed;
    try {
      allowed = await cache.getVersions(ref);
    } on PackageNotFoundException catch (error) {
      // Show the user why the package was being requested.
      throw new DependencyNotFoundException(
          ref.name, error, _selection.getDependenciesOn(ref.name).toList());
    }

    if (_forceLatest.contains(ref.name)) allowed = [allowed.first];

    if (locked != null) {
      allowed = allowed.where((version) => version != locked);
    }

    return allowed;
  }

  /// Backtracks from the current failed solution and determines the next
  /// solution to try.
  ///
  /// This backjumps based on the cause of previous failures to minimize
  /// backtracking.
  ///
  /// Returns `true` if there is a new solution to try.
  Future<bool> _backtrack() async {
    // Bail if there is nothing to backtrack to.
    if (_versions.isEmpty) return false;

    // TODO(nweiz): Use real while loops when issue 23394 is fixed.

    // Advance past the current version of the leaf-most package.
    await Future.doWhile(() async {
      // Move past any packages that couldn't have led to the failure.
      await Future.doWhile(() async {
        if (_versions.isEmpty || _versions.last.hasFailed) return false;
        var queue = _versions.removeLast();
        assert(_selection.ids.last == queue.current);
        await _selection.unselectLast();
        return true;
      });

      if (_versions.isEmpty) return false;

      var queue = _versions.last;
      var name = queue.current.name;
      assert(_selection.ids.last == queue.current);
      await _selection.unselectLast();

      // Fast forward through versions to find one that's valid relative to the
      // current constraints.
      var foundVersion = false;
      if (await queue.advance()) {
        try {
          await _findValidVersion(queue);
          foundVersion = true;
        } on SolveFailure {
          // `foundVersion` is already false.
        }
      }

      // If we found a valid version, add it to the selection and stop
      // backtracking. Otherwise, backtrack through this package and on.
      if (foundVersion) {
        await _selection.select(queue.current);
        logSolve();
        return false;
      } else {
        logSolve('no more versions of $name, backtracking');
        _versions.removeLast();
        return true;
      }
    });

    if (_versions.isNotEmpty) _attemptedSolutions++;
    return _versions.isNotEmpty;
  }

  /// Rewinds [queue] until it reaches a version that's valid relative to the
  /// current constraints.
  ///
  /// If the first version is valid, no rewinding will be done. If no version is
  /// valid, this throws a [SolveFailure] explaining why.
  Future _findValidVersion(VersionQueue queue) {
    // TODO(nweiz): Use real while loops when issue 23394 is fixed.
    return Future.doWhile(() async {
      try {
        await _checkVersion(queue.current);
        return false;
      } on SolveFailure {
        var name = queue.current.name;
        if (await queue.advance()) return true;

        // If we've run out of valid versions for this package, mark its oldest
        // depender as failing. This ensures that we look at graphs in which the
        // package isn't selected at all.
        _fail(_selection.getDependenciesOn(name).first.depender.name);

        // TODO(nweiz): Throw a more detailed error here that combines all the
        // errors that were thrown for individual versions and fully explains
        // why we couldn't select any versions.

        // The queue is out of versions, so throw the final error we
        // encountered while trying to find one.
        rethrow;
      }
    });
  }

  /// Checks whether the package identified by [id] is valid relative to the
  /// current constraints.
  ///
  /// If it's not, throws a [SolveFailure] explaining why.
  Future _checkVersion(PackageId id) async {
    _checkVersionMatchesConstraint(id);

    var pubspec;
    try {
      pubspec = await _getPubspec(id);
    } on PubspecException catch (error) {
      // The lockfile for the pubspec couldn't be parsed,
      log.fine("Failed to parse pubspec for $id:\n$error");
      throw new NoVersionException(id.name, null, id.version, []);
    } on PackageNotFoundException {
      // We can only get here if the lockfile refers to a specific package
      // version that doesn't exist (probably because it was yanked).
      throw new NoVersionException(id.name, null, id.version, []);
    }

    _checkPubspecMatchesSdkConstraint(pubspec);
    _checkPubspecMatchesFeatures(pubspec);

    for (var feature in pubspec.features.values) {
      if (!_selection.isFeatureEnabled(id.name, feature)) continue;
      _checkFeatureMatchesSdk(id, feature);
    }

    await _checkDependencies(id, await depsFor(id));

    return true;
  }

  /// Throws a [SolveFailure] if [id] doesn't match existing version constraints
  /// on the package.
  void _checkVersionMatchesConstraint(PackageId id) {
    var constraint = _selection.getConstraint(id.name);
    if (!constraint.allows(id.version)) {
      var deps = _selection.getDependenciesOn(id.name);

      for (var dep in deps) {
        if (dep.dep.constraint.allows(id.version)) continue;
        _fail(dep.depender.name);
      }

      logSolve(
          "version ${id.version} of ${id.name} doesn't match $constraint:\n" +
              _selection.describeDependencies(id.name));
      throw new NoVersionException(
          id.name, id.version, constraint, deps.toList());
    }
  }

  /// Throws a [SolveFailure] if [pubspec]'s SDK constraint isn't compatible
  /// with the current SDK.
  void _checkPubspecMatchesSdkConstraint(Pubspec pubspec) {
    if (_overrides.containsKey(pubspec.name)) return;

    if (!pubspec.dartSdkConstraint.allows(sdk.version)) {
      throw new BadSdkVersionException(
          pubspec.name,
          'Package ${pubspec.name} requires SDK version '
          '${pubspec.dartSdkConstraint} but the current SDK is '
          '${sdk.version}.');
    }

    if (pubspec.flutterSdkConstraint != null) {
      if (!flutter.isAvailable) {
        throw new BadSdkVersionException(
            pubspec.name,
            'Package ${pubspec.name} requires the Flutter SDK, which is not '
            'available.');
      }

      if (!pubspec.flutterSdkConstraint.allows(flutter.version)) {
        throw new BadSdkVersionException(
            pubspec.name,
            'Package ${pubspec.name} requires Flutter SDK version '
            '${pubspec.flutterSdkConstraint} but the current SDK is '
            '${flutter.version}.');
      }
    }
  }

  /// Throws a [SolveFailure] if [pubspec] doesn't have features that are
  /// required for its package.
  void _checkPubspecMatchesFeatures(Pubspec pubspec) {
    var dependencies = _selection.getDependenciesOn(pubspec.name);
    for (var dep in dependencies) {
      dep.dep.features.forEach((featureName, type) {
        if (type != FeatureDependency.required) return;
        if (pubspec.features.containsKey(featureName)) return;

        throw new MissingFeatureException(
            pubspec.name, pubspec.version, featureName, dependencies);
      });
    }
  }

  /// Throws a [SolveFailure] if [deps] are inconsistent with the existing state
  /// of the version solver.
  Future _checkDependencies(
      PackageId depender, Iterable<PackageRange> deps) async {
    for (var dep in deps) {
      if (dep.isMagic) continue;

      var dependency = new Dependency(depender, dep);
      var allDeps = _selection.getDependenciesOn(dep.name).toList();
      allDeps.add(dependency);

      _checkDependencyMatchesMetadata(dependency, allDeps);
      await _checkDependencyMatchesSelection(dependency, allDeps);
      _checkDependencyMatchesConstraint(dependency, allDeps);
    }
  }

  /// Throws a [SolveFailure] if [dep] is inconsistent with existing
  /// dependencies on the same package.
  void _checkDependencyMatchesConstraint(
      Dependency dep, List<Dependency> allDeps) {
    var depConstraint = _selection.getConstraint(dep.dep.name);
    if (!depConstraint.allowsAny(dep.dep.constraint)) {
      for (var otherDep in _selection.getDependenciesOn(dep.dep.name)) {
        if (otherDep.dep.constraint.allowsAny(dep.dep.constraint)) continue;
        _fail(otherDep.depender.name);
      }

      logSolve('inconsistent constraints on ${dep.dep.name}:\n'
          '  $dep\n' +
          _selection.describeDependencies(dep.dep.name));
      throw new DisjointConstraintException(dep.dep.name, allDeps);
    }
  }

  /// Throws a [SolveFailure] if the source and description of [dep] doesn't
  /// match the existing dependencies on the same package.
  void _checkDependencyMatchesMetadata(
      Dependency dep, List<Dependency> allDeps) {
    var required = _selection.getRequiredDependency(dep.dep.name);
    if (required == null) return;

    if (dep.dep.source != required.dep.source) {
      // Mark the dependers as failing rather than the package itself, because
      // no version from this source will be compatible.
      for (var otherDep in _selection.getDependenciesOn(dep.dep.name)) {
        _fail(otherDep.depender.name);
      }

      logSolve('inconsistent source "${dep.dep.source}" for ${dep.dep.name}:\n'
          '  $dep\n' +
          _selection.describeDependencies(dep.dep.name));
      throw new SourceMismatchException(dep.dep.name, allDeps);
    }

    if (!dep.dep.samePackage(required.dep)) {
      // Mark the dependers as failing rather than the package itself, because
      // no version with this description will be compatible.
      for (var otherDep in _selection.getDependenciesOn(dep.dep.name)) {
        _fail(otherDep.depender.name);
      }

      logSolve(
          'inconsistent description "${dep.dep.description}" for ${dep.dep.name}:\n'
              '  $dep\n' +
              _selection.describeDependencies(dep.dep.name));
      throw new DescriptionMismatchException(dep.dep.name, allDeps);
    }
  }

  /// Throws a [SolveFailure] if [dep] doesn't match the version of the package
  /// that has already been selected.
  Future _checkDependencyMatchesSelection(
      Dependency dep, List<Dependency> allDeps) async {
    var selected = _selection.selected(dep.dep.name);
    if (selected == null) return;

    if (!dep.dep.constraint.allows(selected.version)) {
      _fail(dep.dep.name);

      logSolve(
          "constraint doesn't match selected version ${selected.version} of "
          "${dep.dep.name}:\n"
          "  $dep");
      throw new NoVersionException(
          dep.dep.name, selected.version, dep.dep.constraint, allDeps);
    }

    var pubspec = await _getPubspec(selected);

    // Verify that any features enabled by [dep] have valid dependencies.
    for (var feature in pubspec.features.values) {
      // If the feature is already enabled, we don't need to re-check its
      // dependencies.
      if (_selection.isFeatureEnabled(dep.dep.name, feature)) continue;

      // If [dep] doesn't enable the feature, don't check its dependencies.
      if (!feature.isEnabled(dep.dep.features)) continue;

      _checkFeatureMatchesSdk(selected, feature);
      await _checkDependencies(selected, feature.dependencies);
    }

    // Verify that all features that are depended on actually exist in the package.
    dep.dep.features.forEach((featureName, type) {
      if (type != FeatureDependency.required) return;
      if (pubspec.features.containsKey(featureName)) return;

      _fail(dep.dep.name);

      logSolve("selected version of ${dep.dep.name} doesn't have feature "
          "$featureName:\n"
          "  $dep");
      throw new MissingFeatureException(
          dep.dep.name, selected.version, featureName, allDeps);
    });
  }

  /// Throws a [SolveFailure] if [feature]'s SDK constraints aren't compatible
  /// with the current SDK.
  void _checkFeatureMatchesSdk(PackageId id, Feature feature) {
    if (_overrides.containsKey(id.name)) return;

    if (!feature.dartSdkConstraint.allows(sdk.version)) {
      throw new BadSdkVersionException(
          id.name,
          'Package ${id.name} feature ${feature.name} requires SDK version '
          '${feature.dartSdkConstraint} but the current SDK is '
          '${sdk.version}.');
    }

    if (feature.flutterSdkConstraint != null) {
      if (!flutter.isAvailable) {
        throw new BadSdkVersionException(
            id.name,
            'Package ${id.name} feature ${feature.name} requires the Flutter '
            'SDK, which is not available.');
      }

      if (!feature.flutterSdkConstraint.allows(flutter.version)) {
        throw new BadSdkVersionException(
            id.name,
            'Package ${id.name} feature ${feature.name} requires Flutter SDK '
            'version ${feature.flutterSdkConstraint} but the current SDK is '
            '${flutter.version}.');
      }
    }
  }

  /// Marks the package named [name] as having failed.
  ///
  /// This will cause the backtracker not to jump over this package.
  void _fail(String name) {
    // Don't mark the root package as failing because it's not in [_versions]
    // and there's only one version of it anyway.
    if (name == root.name) return;
    _versions.firstWhere((queue) => queue.current.name == name).fail();
  }

  /// Returns the dependencies of the package identified by [id].
  ///
  /// This takes overrides, dev dependencies, and features into account when
  /// neccessary.
  Future<Set<PackageRange>> depsFor(PackageId id) async {
    var pubspec = await _getPubspec(id);
    var deps = pubspec.dependencies.toSet();

    for (var feature in pubspec.features.values) {
      if (!_selection.isFeatureEnabled(id.name, feature)) continue;
      deps.addAll(feature.dependencies);
    }

    if (id.isRoot) {
      // Include dev dependencies of the root package.
      deps.addAll(pubspec.devDependencies);

      // Add all overrides. This ensures a dependency only present as an
      // override is still included.
      deps.addAll(_overrides.values);
    }

    return _processDependencies(id, deps);
  }

  /// Returns the dependencies of package identified by [id] that are
  /// newly-activated by [features].
  Future<Set<PackageRange>> newDepsFor(
      PackageId id, Map<String, FeatureDependency> features) async {
    var pubspec = await _getPubspec(id);
    if (pubspec.features.isEmpty) return const UnmodifiableSetView.empty();

    var deps = new Set();
    for (var feature in pubspec.features.values) {
      // Only enable features that weren't already enabled.
      if ((features[feature.name]?.isEnabled ?? feature.onByDefault) &&
          !_selection.isFeatureEnabled(id.name, feature)) {
        deps.addAll(feature.dependencies);
      }
    }

    return _processDependencies(id, deps);
  }

  /// Post-processes [deps] before returning it from [depsFor] or
  /// [depsForFeature].
  ///
  /// This may modify [deps].
  Set<PackageRange> _processDependencies(PackageId id, Set<PackageRange> deps) {
    if (id.isRoot) {
      // Replace any overridden dependencies.
      deps = deps.map((dep) {
        var override = _overrides[dep.name];
        if (override != null) return override;

        // Not overridden.
        return dep;
      }).toSet();
    } else {
      // Ignore any overridden dependencies.
      deps.removeWhere((dep) => _overrides.containsKey(dep.name));

      // If an overridden dependency depends on the root package, ignore that
      // dependency. This ensures that users can work on the next version of one
      // side of a circular dependency easily.
      if (_overrides.containsKey(id.name)) {
        deps.removeWhere((dep) => dep.name == root.name);
      }
    }

    // Make sure the package doesn't have any bad dependencies.
    for (var dep in deps.toSet()) {
      if (!dep.isRoot && dep.source is UnknownSource) {
        throw new UnknownSourceException(id.name, [new Dependency(id, dep)]);
      }

      if (dep.name == 'barback') {
        deps.add(new PackageRange.magic('pub itself'));
      }
    }

    return deps;
  }

  /// Loads and returns the pubspec for [id].
  Future<Pubspec> _getPubspec(PackageId id) async {
    if (id.isRoot) return root.pubspec;
    if (id.isMagic && id.name == 'pub itself') return _implicitPubspec;

    return await withDependencyType(root.dependencyType(id.name),
        () => systemCache.source(id.source).describe(id));
  }

  /// Logs the initial parameters to the solver.
  void _logParameters() {
    var buffer = new StringBuffer();
    buffer.writeln("Solving dependencies:");
    for (var package in root.dependencies) {
      buffer.write("- $package");
      var locked = getLocked(package.name);
      if (_forceLatest.contains(package.name)) {
        buffer.write(" (use latest)");
      } else if (locked != null) {
        var version = locked.version;
        buffer.write(" (locked to $version)");
      }
      buffer.writeln();
    }
    log.solver(buffer.toString().trim());
  }

  /// Logs [message] in the context of the current selected packages.
  ///
  /// If [message] is omitted, just logs a description of leaf-most selection.
  void logSolve([String message]) {
    if (message == null) {
      if (_versions.isEmpty) {
        message = "* start at root";
      } else {
        message = "* select ${_versions.last.current}";
      }
    } else {
      // Otherwise, indent it under the current selected package.
      message = prefixLines(message);
    }

    // Indent for the previous selections.
    log.solver(prefixLines(message, prefix: '| ' * _versions.length));
  }
}
