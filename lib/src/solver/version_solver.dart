// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source/unknown.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'assignment.dart';
import 'failure.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';
import 'package_lister.dart';
import 'partial_solution.dart';
import 'reformat_ranges.dart';
import 'result.dart';
import 'set_relation.dart';
import 'term.dart';
import 'type.dart';

// TODO(nweiz): Currently, a bunch of tests that use the solver are skipped
// because they exercise parts of the solver that haven't been reimplemented.
// They should all be re-enabled before this gets released.

/// The version solver that finds a set of package versions that satisfy the
/// root package's dependencies.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md for details
/// on how this solver works.
class VersionSolver {
  /// All known incompatibilities, indexed by package name.
  ///
  /// Each incompatibility is indexed by each package it refers to, and so may
  /// appear in multiple values.
  final _incompatibilities = <String, List<Incompatibility>>{};

  /// The partial solution that contains package versions we've selected and
  /// assignments we've derived from those versions and [_incompatibilities].
  final _solution = PartialSolution();

  /// Package listers that lazily convert package versions' dependencies into
  /// incompatibilities.
  final _packageListers = <PackageRef, PackageLister>{};

  /// The type of version solve being performed.
  final SolveType _type;

  /// The system cache in which packages are stored.
  final SystemCache _systemCache;

  /// The entrypoint package, whose dependencies seed the version solve process.
  final Package _root;

  /// The lockfile, indicating which package versions were previously selected.
  final LockFile _lockFile;

  /// The set of package names that were overridden by the root package, for
  /// which other packages' constraints should be ignored.
  final Set<String> _overriddenPackages;

  /// The set of packages for which the lockfile should be ignored and only the
  /// most recent versions should be used.
  final Set<String> _useLatest;

  /// The set of packages for which we've added an incompatibility that forces
  /// the latest version to be used.
  final _haveUsedLatest = <PackageRef>{};

  VersionSolver(this._type, this._systemCache, this._root, this._lockFile,
      Iterable<String> useLatest)
      : _overriddenPackages = MapKeySet(_root.pubspec.dependencyOverrides),
        _useLatest = Set.from(useLatest);

  /// Finds a set of dependencies that match the root package's constraints, or
  /// throws an error if no such set is available.
  Future<SolveResult> solve() async {
    var stopwatch = Stopwatch()..start();

    _addIncompatibility(Incompatibility(
        [Term(PackageRange.root(_root), false)], IncompatibilityCause.root));

    try {
      return await _systemCache.hosted.withPrefetching(() async {
        var next = _root.name;
        while (next != null) {
          _propagate(next);
          next = await _choosePackageVersion();
        }

        return await _result();
      });
    } finally {
      // Gather some solving metrics.
      log.solver('Version solving took ${stopwatch.elapsed} seconds.\n'
          'Tried ${_solution.attemptedSolutions} solutions.');
    }
  }

  /// Performs [unit propagation][] on incompatibilities transitively related to
  /// [package] to derive new assignments for [_solution].
  ///
  /// [unit propagation]: https://github.com/dart-lang/pub/tree/master/doc/solver.md#unit-propagation
  void _propagate(String package) {
    var changed = {package};

    while (changed.isNotEmpty) {
      var package = changed.first;
      changed.remove(package);

      // Iterate in reverse because conflict resolution tends to produce more
      // general incompatibilities as time goes on. If we look at those first,
      // we can derive stronger assignments sooner and more eagerly find
      // conflicts.
      for (var incompatibility in _incompatibilities[package].reversed) {
        var result = _propagateIncompatibility(incompatibility);
        if (result == #conflict) {
          // If [incompatibility] is satisfied by [_solution], we use
          // [_resolveConflict] to determine the root cause of the conflict as a
          // new incompatibility. It also backjumps to a point in [_solution]
          // where that incompatibility will allow us to derive new assignments
          // that avoid the conflict.
          var rootCause = _resolveConflict(incompatibility);

          // Backjumping erases all the assignments we did at the previous
          // decision level, so we clear [changed] and refill it with the
          // newly-propagated assignment.
          changed.clear();
          changed.add(_propagateIncompatibility(rootCause) as String);
          break;
        } else if (result is String) {
          changed.add(result);
        }
      }
    }
  }

  /// If [incompatibility] is [almost satisfied][] by [_solution], adds the
  /// negation of the unsatisfied term to [_solution].
  ///
  /// [almost satisfied]: https://github.com/dart-lang/pub/tree/master/doc/solver.md#incompatibility
  ///
  /// If [incompatibility] is satisfied by [_solution], returns `#conflict`. If
  /// [incompatibility] is almost satisfied by [_solution], returns the
  /// unsatisfied term's package name. Otherwise, returns `#none`.
  dynamic /* String | #none | #conflict */ _propagateIncompatibility(
      Incompatibility incompatibility) {
    // The first entry in `incompatibility.terms` that's not yet satisfied by
    // [_solution], if one exists. If we find more than one, [_solution] is
    // inconclusive for [incompatibility] and we can't deduce anything.
    Term unsatisfied;

    for (var i = 0; i < incompatibility.terms.length; i++) {
      var term = incompatibility.terms[i];
      var relation = _solution.relation(term);

      if (relation == SetRelation.disjoint) {
        // If [term] is already contradicted by [_solution], then
        // [incompatibility] is contradicted as well and there's nothing new we
        // can deduce from it.
        return #none;
      } else if (relation == SetRelation.overlapping) {
        // If more than one term is inconclusive, we can't deduce anything about
        // [incompatibility].
        if (unsatisfied != null) return #none;

        // If exactly one term in [incompatibility] is inconclusive, then it's
        // almost satisfied and [term] is the unsatisfied term. We can add the
        // inverse of the term to [_solution].
        unsatisfied = term;
      }
    }

    // If *all* terms in [incompatibility] are satisfied by [_solution], then
    // [incompatibility] is satisfied and we have a conflict.
    if (unsatisfied == null) return #conflict;

    _log("derived:${unsatisfied.isPositive ? ' not' : ''} "
        '${unsatisfied.package}');
    _solution.derive(
        unsatisfied.package, !unsatisfied.isPositive, incompatibility);
    return unsatisfied.package.name;
  }

  /// Given an [incompatibility] that's satisfied by [_solution], [conflict
  /// resolution][] constructs a new incompatibility that encapsulates the root
  /// cause of the conflict and backtracks [_solution] until the new
  /// incompatibility will allow [_propagate] to deduce new assignments.
  ///
  /// [conflict resolution]: https://github.com/dart-lang/pub/tree/master/doc/solver.md#conflict-resolution
  ///
  /// Adds the new incompatibility to [_incompatibilities] and returns it.
  Incompatibility _resolveConflict(Incompatibility incompatibility) {
    _log("${log.red(log.bold("conflict"))}: $incompatibility");

    var newIncompatibility = false;
    while (!incompatibility.isFailure) {
      // The term in `incompatibility.terms` that was most recently satisfied by
      // [_solution].
      Term mostRecentTerm;

      // The earliest assignment in [_solution] such that [incompatibility] is
      // satisfied by [_solution] up to and including this assignment.
      Assignment mostRecentSatisfier;

      // The difference between [mostRecentSatisfier] and [mostRecentTerm];
      // that is, the versions that are allowed by [mostRecentSatisfier] and not
      // by [mostRecentTerm]. This is `null` if [mostRecentSatisfier] totally
      // satisfies [mostRecentTerm].
      Term difference;

      // The decision level of the earliest assignment in [_solution] *before*
      // [mostRecentSatisfier] such that [incompatibility] is satisfied by
      // [_solution] up to and including this assignment plus
      // [mostRecentSatisfier].
      //
      // Decision level 1 is the level where the root package was selected. It's
      // safe to go back to decision level 0, but stopping at 1 tends to produce
      // better error messages, because references to the root package end up
      // closer to the final conclusion that no solution exists.
      var previousSatisfierLevel = 1;

      for (var term in incompatibility.terms) {
        var satisfier = _solution.satisfier(term);
        if (mostRecentSatisfier == null) {
          mostRecentTerm = term;
          mostRecentSatisfier = satisfier;
        } else if (mostRecentSatisfier.index < satisfier.index) {
          previousSatisfierLevel = math.max(
              previousSatisfierLevel, mostRecentSatisfier.decisionLevel);
          mostRecentTerm = term;
          mostRecentSatisfier = satisfier;
          difference = null;
        } else {
          previousSatisfierLevel =
              math.max(previousSatisfierLevel, satisfier.decisionLevel);
        }

        if (mostRecentTerm == term) {
          // If [mostRecentSatisfier] doesn't satisfy [mostRecentTerm] on its
          // own, then the next-most-recent satisfier may be the one that
          // satisfies the remainder.
          difference = mostRecentSatisfier.difference(mostRecentTerm);
          if (difference != null) {
            previousSatisfierLevel = math.max(previousSatisfierLevel,
                _solution.satisfier(difference.inverse).decisionLevel);
          }
        }
      }

      // If [mostRecentSatisfier] is the only satisfier left at its decision
      // level, or if it has no cause (indicating that it's a decision rather
      // than a derivation), then [incompatibility] is the root cause. We then
      // backjump to [previousSatisfierLevel], where [incompatibility] is
      // guaranteed to allow [_propagate] to produce more assignments.
      if (previousSatisfierLevel < mostRecentSatisfier.decisionLevel ||
          mostRecentSatisfier.cause == null) {
        _solution.backtrack(previousSatisfierLevel);
        if (newIncompatibility) _addIncompatibility(incompatibility);
        return incompatibility;
      }

      // Create a new incompatibility by combining [incompatibility] with the
      // incompatibility that caused [mostRecentSatisfier] to be assigned. Doing
      // this iteratively constructs an incompatibility that's guaranteed to be
      // true (that is, we know for sure no solution will satisfy the
      // incompatibility) while also approximating the intuitive notion of the
      // "root cause" of the conflict.
      var newTerms = <Term>[
        for (var term in incompatibility.terms)
          if (term != mostRecentTerm) term,
        for (var term in mostRecentSatisfier.cause.terms)
          if (term.package != mostRecentSatisfier.package) term,
      ];

      // The [mostRecentSatisfier] may not satisfy [mostRecentTerm] on its own
      // if there are a collection of constraints on [mostRecentTerm] that
      // only satisfy it together. For example, if [mostRecentTerm] is
      // `foo ^1.0.0` and [_solution] contains `[foo >=1.0.0,
      // foo <2.0.0]`, then [mostRecentSatisfier] will be `foo <2.0.0` even
      // though it doesn't totally satisfy `foo ^1.0.0`.
      //
      // In this case, we add `not (mostRecentSatisfier \ mostRecentTerm)` to
      // the incompatibility as well, See [the algorithm documentation][] for
      // details.
      //
      // [the algorithm documentation]: https://github.com/dart-lang/pub/tree/master/doc/solver.md#conflict-resolution
      if (difference != null) newTerms.add(difference.inverse);

      incompatibility = Incompatibility(
          newTerms, ConflictCause(incompatibility, mostRecentSatisfier.cause));
      newIncompatibility = true;

      var partially = difference == null ? '' : ' partially';
      var bang = log.red('!');
      _log('$bang $mostRecentTerm is$partially satisfied by '
          '$mostRecentSatisfier');
      _log('$bang which is caused by "${mostRecentSatisfier.cause}"');
      _log('$bang thus: $incompatibility');
    }

    throw SolveFailure(reformatRanges(_packageListers, incompatibility));
  }

  /// Tries to select a version of a required package.
  ///
  /// Returns the name of the package whose incompatibilities should be
  /// propagated by [_propagate], or `null` indicating that version solving is
  /// complete and a solution has been found.
  Future<String> _choosePackageVersion() async {
    var unsatisfied = _solution.unsatisfied.toList();
    if (unsatisfied.isEmpty) return null;

    // If we require a package from an unknown source, add an incompatibility
    // that will force a conflict for that package.
    for (var candidate in unsatisfied) {
      if (_useLatest.contains(candidate.name) &&
          candidate.source.hasMultipleVersions) {
        var ref = candidate.toRef();
        if (_haveUsedLatest.add(ref)) {
          // All versions of [ref] other than the latest are forbidden.
          var latestVersion = (await _packageLister(ref).latest).version;
          _addIncompatibility(Incompatibility([
            Term(
                ref.withConstraint(
                    VersionConstraint.any.difference(latestVersion)),
                true),
          ], IncompatibilityCause.useLatest));
          return candidate.name;
        }
      }

      if (candidate.source is! UnknownSource) continue;
      _addIncompatibility(Incompatibility(
          [Term(candidate.withConstraint(VersionConstraint.any), true)],
          IncompatibilityCause.unknownSource));
      return candidate.name;
    }

    /// Prefer packages with as few remaining versions as possible, so that if a
    /// conflict is necessary it's forced quickly.
    var package = await minByAsync(unsatisfied, (package) async {
      // If we're forced to use the latest version of a package, it effectively
      // only has one version to choose from.
      if (_useLatest.contains(package.name)) return 1;
      return await _packageLister(package).countVersions(package.constraint);
    });

    PackageId version;
    try {
      version = await _packageLister(package).bestVersion(package.constraint);
    } on PackageNotFoundException catch (error) {
      _addIncompatibility(Incompatibility(
          [Term(package.withConstraint(VersionConstraint.any), true)],
          PackageNotFoundCause(error)));
      return package.name;
    }

    if (version == null) {
      // If the constraint excludes only a single version, it must have come
      // from the inverse of a lockfile's dependency. In that case, we request
      // any version instead so that the lister gives us more general
      // incompatibilities. This makes error reporting much nicer.
      if (_excludesSingleVersion(package.constraint)) {
        version =
            await _packageLister(package).bestVersion(VersionConstraint.any);
      } else {
        // If there are no versions that satisfy [package.constraint], add an
        // incompatibility that indicates that.
        _addIncompatibility(Incompatibility(
            [Term(package, true)], IncompatibilityCause.noVersions));
        return package.name;
      }
    }

    var conflict = false;
    for (var incompatibility
        in await _packageLister(package).incompatibilitiesFor(version)) {
      _addIncompatibility(incompatibility);

      // If an incompatibility is already satisfied, then selecting [version]
      // would cause a conflict. We'll continue adding its dependencies, then go
      // back to unit propagation which will guide us to choose a better
      // version.
      conflict = conflict ||
          incompatibility.terms.every((term) =>
              term.package.name == package.name || _solution.satisfies(term));
    }

    if (!conflict) {
      _solution.decide(version);
      _log('selecting $version');
    }

    return package.name;
  }

  /// Adds [incompatibility] to [_incompatibilities].
  void _addIncompatibility(Incompatibility incompatibility) {
    _log('fact: $incompatibility');

    for (var term in incompatibility.terms) {
      _incompatibilities
          .putIfAbsent(term.package.name, () => [])
          .add(incompatibility);
    }
  }

  /// Returns whether [constraint] allows all versions except one.
  bool _excludesSingleVersion(VersionConstraint constraint) =>
      VersionConstraint.any.difference(constraint) is Version;

  /// Creates a [SolveResult] from the decisions in [_solution].
  Future<SolveResult> _result() async {
    var decisions = _solution.decisions.toList();
    var pubspecs = <String, Pubspec>{};
    for (var id in decisions) {
      if (id.isRoot) {
        pubspecs[id.name] = _root.pubspec;
      } else {
        pubspecs[id.name] = await _systemCache.source(id.source).describe(id);
      }
    }

    return SolveResult(
        _systemCache.sources,
        _root,
        _lockFile,
        decisions,
        pubspecs,
        _getAvailableVersions(decisions),
        _solution.attemptedSolutions);
  }

  /// Generates a map containing all of the known available versions for each
  /// package in [packages].
  ///
  /// The version list may not always be complete. If the package is the root
  /// package, or if it's a package that we didn't unlock while solving because
  /// we weren't trying to upgrade it, we will just know the current version.
  Map<String, List<Version>> _getAvailableVersions(List<PackageId> packages) {
    var availableVersions = <String, List<Version>>{};
    for (var package in packages) {
      var cached = _packageListers[package.toRef()]?.cachedVersions;
      // If the version list was never requested, just use the one known
      // version.
      var versions = cached == null
          ? [package.version]
          : cached.map((id) => id.version).toList();

      availableVersions[package.name] = versions;
    }

    return availableVersions;
  }

  /// Returns the package lister for [package], creating it if necessary.
  PackageLister _packageLister(PackageName package) {
    var ref = package.toRef();
    return _packageListers.putIfAbsent(ref, () {
      if (ref.isRoot) return PackageLister.root(_root);

      var locked = _getLocked(ref.name);
      if (locked != null && !locked.samePackage(ref)) locked = null;

      var overridden = _overriddenPackages;
      if (overridden.contains(package.name)) {
        // If the package is overridden, ignore its dependencies back onto the
        // root package.
        overridden = Set.from(overridden)..add(_root.name);
      }

      return PackageLister(_systemCache, ref, locked,
          _root.dependencyType(package.name), overridden,
          downgrade: _type == SolveType.DOWNGRADE);
    });
  }

  /// Gets the version of [ref] currently locked in the lock file.
  ///
  /// Returns `null` if it isn't in the lockfile (or has been unlocked).
  PackageId _getLocked(String package) {
    if (_type == SolveType.GET) return _lockFile.packages[package];

    // When downgrading, we don't want to force the latest versions of
    // non-hosted packages, since they don't support multiple versions and thus
    // can't be downgraded.
    if (_type == SolveType.DOWNGRADE) {
      var locked = _lockFile.packages[package];
      if (locked != null && !locked.source.hasMultipleVersions) return locked;
    }

    if (_useLatest.isEmpty || _useLatest.contains(package)) return null;
    return _lockFile.packages[package];
  }

  /// Logs [message] in the context of the current selected packages.
  ///
  /// If [message] is omitted, just logs a description of leaf-most selection.
  void _log([String message]) {
    // Indent for the previous selections.
    log.solver(prefixLines(message, prefix: '  ' * _solution.decisionLevel));
  }
}
