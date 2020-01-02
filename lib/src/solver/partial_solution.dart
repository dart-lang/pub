// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';
import 'assignment.dart';
import 'incompatibility.dart';
import 'set_relation.dart';
import 'term.dart';

/// A list of [Assignment]s that represent the solver's current best guess about
/// what's true for the eventual set of package versions that will comprise the
/// total solution.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#partial-solution.
class PartialSolution {
  /// The assignments that have been made so far, in the order they were
  /// assigned.
  final _assignments = <Assignment>[];

  /// The decisions made for each package.
  final _decisions = <String, PackageId>{};

  /// The intersection of all positive [Assignment]s for each package, minus any
  /// negative [Assignment]s that refer to that package.
  ///
  /// This is derived from [_assignments].
  final _positive = <String, Term>{};

  /// The union of all negative [Assignment]s for each package.
  ///
  /// If a package has any positive [Assignment]s, it doesn't appear in this
  /// map.
  ///
  /// This is derived from [_assignments].
  final _negative = <String, Map<PackageRef, Term>>{};

  /// Returns all the decisions that have been made in this partial solution.
  Iterable<PackageId> get decisions => _decisions.values;

  /// Returns all [PackageRange]s that have been assigned but are not yet
  /// satisfied.
  Iterable<PackageRange> get unsatisfied => _positive.values
      .where((term) => !_decisions.containsKey(term.package.name))
      .map((term) => term.package);

  // The current decision level—that is, the length of [decisions].
  int get decisionLevel => _decisions.length;

  /// The number of distinct solutions that have been attempted so far.
  int get attemptedSolutions => _attemptedSolutions;
  var _attemptedSolutions = 1;

  /// Whether the solver is currently backtracking.
  var _backtracking = false;

  /// Adds an assignment of [package] as a decision and increments the
  /// [decisionLevel].
  void decide(PackageId package) {
    // When we make a new decision after backtracking, count an additional
    // attempted solution. If we backtrack multiple times in a row, though, we
    // only want to count one, since we haven't actually started attempting a
    // new solution.
    if (_backtracking) _attemptedSolutions++;
    _backtracking = false;
    _decisions[package.name] = package;
    _assign(Assignment.decision(package, decisionLevel, _assignments.length));
  }

  /// Adds an assignment of [package] as a derivation.
  void derive(PackageName package, bool isPositive, Incompatibility cause) {
    _assign(Assignment.derivation(
        package, isPositive, cause, decisionLevel, _assignments.length));
  }

  /// Adds [assignment] to [_assignments] and [_positive] or [_negative].
  void _assign(Assignment assignment) {
    _assignments.add(assignment);
    _register(assignment);
  }

  /// Resets the current decision level to [decisionLevel], and removes all
  /// assignments made after that level.
  void backtrack(int decisionLevel) {
    _backtracking = true;

    var packages = <String>{};
    while (_assignments.last.decisionLevel > decisionLevel) {
      var removed = _assignments.removeLast();
      packages.add(removed.package.name);
      if (removed.isDecision) _decisions.remove(removed.package.name);
    }

    // Re-compute [_positive] and [_negative] for the packages that were removed.
    for (var package in packages) {
      _positive.remove(package);
      _negative.remove(package);
    }

    for (var assignment in _assignments) {
      if (packages.contains(assignment.package.name)) {
        _register(assignment);
      }
    }
  }

  /// Registers [assignment] in [_positive] or [_negative].
  void _register(Assignment assignment) {
    var name = assignment.package.name;
    var oldPositive = _positive[name];
    if (oldPositive != null) {
      _positive[name] = oldPositive.intersect(assignment);
      return;
    }

    var ref = assignment.package.toRef();
    var negativeByRef = _negative[name];
    var oldNegative = negativeByRef == null ? null : negativeByRef[ref];
    var term =
        oldNegative == null ? assignment : assignment.intersect(oldNegative);

    if (term.isPositive) {
      _negative.remove(name);
      _positive[name] = term;
    } else {
      _negative.putIfAbsent(name, () => {})[ref] = term;
    }
  }

  /// Returns the first [Assignment] in this solution such that the sublist of
  /// assignments up to and including that entry collectively satisfies [term].
  ///
  /// Throws a [StateError] if [term] isn't satisfied by [this].
  Assignment satisfier(Term term) {
    Term assignedTerm;
    for (var assignment in _assignments) {
      if (assignment.package.name != term.package.name) continue;

      if (!assignment.package.isRoot &&
          !assignment.package.samePackage(term.package)) {
        // not foo from hosted has no bearing on foo from git
        if (!assignment.isPositive) continue;

        // foo from hosted satisfies not foo from git
        assert(!term.isPositive);
        return assignment;
      }

      assignedTerm = assignedTerm == null
          ? assignment
          : assignedTerm.intersect(assignment);

      // As soon as we have enough assignments to satisfy [term], return them.
      if (assignedTerm.satisfies(term)) return assignment;
    }

    throw StateError('[BUG] $term is not satisfied.');
  }

  /// Returns whether [this] satisfies [other].
  ///
  /// That is, whether [other] must be true given the assignments in this
  /// partial solution.
  bool satisfies(Term term) => relation(term) == SetRelation.subset;

  /// Returns the relationship between the package versions allowed by all
  /// assignments in [this] and those allowed by [term].
  SetRelation relation(Term term) {
    var positive = _positive[term.package.name];
    if (positive != null) return positive.relation(term);

    // If there are no assignments related to [term], that means the
    // assignments allow any version of any package, which is a superset of
    // [term].
    var byRef = _negative[term.package.name];
    if (byRef == null) return SetRelation.overlapping;

    // not foo from git is a superset of foo from hosted
    // not foo from git overlaps not foo from hosted
    var negative = byRef[term.package.toRef()];
    if (negative == null) return SetRelation.overlapping;

    return negative.relation(term);
  }
}
