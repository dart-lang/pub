// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:pub_semver/pub_semver.dart';

import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'assignment.dart';
import 'failure.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';
import 'package_lister.dart';
import 'partial_solution.dart';
import 'result.dart';
import 'set_relation.dart';
import 'term.dart';
import 'type.dart';

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
  final _solution = new PartialSolution();

  /// Package listers that lazily convert package versions' dependencies into
  /// incompatibilities.
  final _packageListers = <PackageRef, PackageLister>{};

  /// The type of version solve being performed.
  final SolveType _type;

  /// The system cache in which packages are stored.
  final SystemCache _systemCache;

  /// The entrypoint package, whose dependencies seed the version solve process.
  final Package _root;

  VersionSolver(this._type, this._systemCache, this._root, LockFile lockFile,
      List<String> useLatest);

  /// Finds a set of dependencies that match the root package's constraints, or
  /// throws an error if no such set is available.
  Future<SolveResult> solve() async {
    var stopwatch = new Stopwatch()..start();

    var rootId = new PackageId.root(_root);
    var rootIncompatibility = new Incompatibility(
        [new Term(rootId, false)], IncompatibilityCause.root);
    _addIncompatibility(rootIncompatibility);
    for (var dependency in _root.immediateDependencies.values) {
      _addIncompatibility(new Incompatibility(
          [new Term(rootId, true), new Term(dependency, false)],
          IncompatibilityCause.dependency));
    }

    var next = _root.name;
    while (next != null) {
      _propagate(next);
      next = await _choosePackageVersion();
    }

    var result = await _result();

    // Gather some solving metrics.
    log.solver('Version solving took ${stopwatch.elapsed} seconds.\n'
        'Tried ${_solution.attemptedSolutions} solutions.');

    return result;
  }

  /// Performs [unit propagation][] on incompatibilities transitively related to
  /// [package] to derive new assignments for [_solution].
  ///
  /// [unit propagation]: https://github.com/dart-lang/pub/tree/master/doc/solver.md#unit-propagation
  void _propagate(String package) {
    var changed = new Set.from([package]);

    while (!changed.isEmpty) {
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

    // If *all* terms in [incompatibility] are satsified by [_solution], then
    // [incompatibility] is satisfied and we have a conflict.
    if (unsatisfied == null) return #conflict;

    _log("derived: ${unsatisfied.isPositive ? 'not ' : ''}"
        "${unsatisfied.package.toTerseString()}");
    _solution.assign(unsatisfied.package, !unsatisfied.isPositive,
        cause: incompatibility);
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
      // satisfied by [_solution.assignments] up to and including this
      // assignment.
      Assignment mostRecentSatisfier;

      // The difference between [mostRecentSatisfier] and [mostRecentTerm];
      // that is, the versions that are allowed by [mostRecentSatisfier] and not
      // by [mostRecentTerm]. This is `null` if [mostRecentSatisfier] totally
      // satisfies [mostRecentTerm].
      Term difference;

      // The decision level of the earliest assignment in [_solution] *before*
      // [mostRecentSatisfier] such that [incompatibility] is satisfied by
      // [_solution.assignments] up to and including this assignment plus
      // [mostRecentSatisfier].
      var maxDecisionLevel = 0;

      for (var term in incompatibility.terms) {
        var satisfier = _solution.satisfier(term);
        if (mostRecentSatisfier == null) {
          mostRecentTerm = term;
          mostRecentSatisfier = satisfier;
        } else if (mostRecentSatisfier.index < satisfier.index) {
          maxDecisionLevel =
              math.max(maxDecisionLevel, mostRecentSatisfier.decisionLevel);
          mostRecentTerm = term;
          mostRecentSatisfier = satisfier;
          difference = null;
        } else {
          maxDecisionLevel =
              math.max(maxDecisionLevel, satisfier.decisionLevel);
        }

        if (mostRecentTerm == term) {
          // If [mostRecentSatisfier] doesn't satisfy [mostRecentTerm] on its
          // own, then the next-most-recent satisfier may be the one that
          // satisfies the remainder.
          difference = mostRecentSatisfier.difference(mostRecentTerm);
          if (difference != null) {
            maxDecisionLevel = math.max(maxDecisionLevel,
                _solution.satisfier(difference.inverse).decisionLevel);
          }
        }
      }

      // If [mostRecentSatisfier] is the only satisfier left at its decision
      // level, or if it has no cause (indicating that it's a decision rather
      // than a derivation), then [incompatibility] is the root cause. We then
      // backjump to [maxDecisionLevel], where [incompatibility] is guaranteed
      // to allow [_propagate] to produce more assignments.
      if (maxDecisionLevel < mostRecentSatisfier.decisionLevel ||
          mostRecentSatisfier.cause == null) {
        _solution.backtrack(maxDecisionLevel);
        if (newIncompatibility) _addIncompatibility(incompatibility);
        return incompatibility;
      }

      // Create a new incompatibility by combining [incompatibility] with the
      // incompatibility that caused [mostRecentSatisfier] to be assigned. Doing
      // this iteratively constructs an incompatibility that's guaranteed to be
      // true (that is, we know for sure no solution will satisfy the
      // incompatibility) while also approximating the intuitive notion of the
      // "root cause" of the conflict.
      var newTerms = <Term>[]
        ..addAll(incompatibility.terms.where((term) => term != mostRecentTerm))
        ..addAll(mostRecentSatisfier.cause.terms
            .where((term) => term.package != mostRecentSatisfier.package));

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

      incompatibility = new Incompatibility(newTerms,
          new ConflictCause(incompatibility, mostRecentSatisfier.cause));
      newIncompatibility = true;

      var partially = difference == null ? "" : " partially";
      var bang = log.red('!');
      _log('$bang $mostRecentTerm is$partially satisfied by '
          '$mostRecentSatisfier');
      _log('$bang which is caused by "${mostRecentSatisfier.cause}"');
      _log("$bang thus: $incompatibility");
    }

    throw new SolveFailure(incompatibility);
  }

  /// Tries to select a version of a required package.
  ///
  /// Returns the name of the package whose incompatibilities should be
  /// propagated by [_propagate], or `null` indicating that version solving is
  /// complete and a solution has been found.
  Future<String> _choosePackageVersion() async {
    var unsatisfied = _solution.positive.values
        .where((term) => term.package is! PackageId)
        .map((term) => term.package as PackageRange)
        .toList();
    if (unsatisfied.isEmpty) return null;

    /// Prefer packages with as few remaining versions as possible, so that if a
    /// conflict is necessary it's forced quickly.
    var package = await minByAsync(unsatisfied,
        (package) => _packageLister(package).countVersions(package.constraint));

    var version = await _packageLister(package).bestVersion(package.constraint);

    if (version == null) {
      // If there are no versions that satisfy [package.constraint], add an
      // incompatibility that indicates that.
      _addIncompatibility(new Incompatibility(
          [new Term(package, true)], IncompatibilityCause.noVersions));
      return package.name;
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
      _solution.assign(version, true, decision: true);
      _log("selecting ${version.toTerseString()}");
    }

    return package.name;
  }

  /// Adds [incompatibility] to [_incompatibilities].
  void _addIncompatibility(Incompatibility incompatibility) {
    _log("fact: $incompatibility");

    for (var term in incompatibility.terms) {
      _incompatibilities
          .putIfAbsent(term.package.name, () => [])
          .add(incompatibility);
    }
  }

  /// Creates a [SolveResult] from the decisions in [_solution].
  Future<SolveResult> _result() async {
    var packages = _solution.assignments
        .where((assignment) => assignment.package is PackageId)
        .map((assignment) => assignment.package as PackageId)
        .toList();

    var pubspecs = <String, Pubspec>{};
    for (var id in packages) {
      if (id.isRoot) {
        pubspecs[id.name] = _root.pubspec;
      } else {
        pubspecs[id.name] = await _systemCache.source(id.source).describe(id);
      }
    }

    var availableVersions = <String, List<Version>>{};
    for (var id in packages) {
      if (id.isRoot) {
        availableVersions[id.name] = [id.version];
      }
    }

    return new SolveResult(
        _systemCache.sources,
        _root,
        new LockFile.empty(),
        packages,
        [],
        pubspecs,
        _getAvailableVersions(packages),
        _solution.attemptedSolutions);
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
    return _packageListers.putIfAbsent(
        ref, () => new PackageLister(_systemCache, ref));
  }

  /// Logs [message] in the context of the current selected packages.
  ///
  /// If [message] is omitted, just logs a description of leaf-most selection.
  void _log([String message]) {
    // Indent for the previous selections.
    log.solver(prefixLines(message, prefix: '  ' * _solution.decisionLevel));
  }
}
