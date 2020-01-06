// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../package_name.dart';
import 'set_relation.dart';

/// A statement about a package which is true or false for a given selection of
/// package versions.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#term.
class Term {
  /// Whether the term is positive or not.
  ///
  /// A positive constraint is true when a package version that matches
  /// [package] is selected; a negative constraint is true when no package
  /// versions that match [package] are selected.
  final bool isPositive;

  /// The range of package versions referred to by this term.
  final PackageRange package;

  /// A copy of this term with the opposite [isPositive] value.
  Term get inverse => Term(package, !isPositive);

  Term(PackageRange package, this.isPositive)
      : package = package.withTerseConstraint();

  VersionConstraint get constraint => package.constraint;

  /// Returns whether [this] satisfies [other].
  ///
  /// That is, whether [this] being true means that [other] must also be true.
  bool satisfies(Term other) =>
      package.name == other.package.name &&
      relation(other) == SetRelation.subset;

  /// Returns the relationship between the package versions allowed by [this]
  /// and by [other].
  ///
  /// Throws an [ArgumentError] if [other] doesn't refer to a package with the
  /// same name as [package].
  SetRelation relation(Term other) {
    if (package.name != other.package.name) {
      throw ArgumentError.value(
          other, 'other', 'should refer to package ${package.name}');
    }

    var otherConstraint = other.constraint;
    if (other.isPositive) {
      if (isPositive) {
        // foo from hosted is disjoint with foo from git
        if (!_compatiblePackage(other.package)) return SetRelation.disjoint;

        // foo ^1.5.0 is a subset of foo ^1.0.0
        if (otherConstraint.allowsAll(constraint)) return SetRelation.subset;

        // foo ^2.0.0 is disjoint with foo ^1.0.0
        if (!constraint.allowsAny(otherConstraint)) return SetRelation.disjoint;

        // foo >=1.5.0 <3.0.0 overlaps foo ^1.0.0
        return SetRelation.overlapping;
      } else {
        // not foo from hosted is a superset foo from git
        if (!_compatiblePackage(other.package)) return SetRelation.overlapping;

        // not foo ^1.0.0 is disjoint with foo ^1.5.0
        if (constraint.allowsAll(otherConstraint)) return SetRelation.disjoint;

        // not foo ^1.5.0 overlaps foo ^1.0.0
        // not foo ^2.0.0 is a superset of foo ^1.5.0
        return SetRelation.overlapping;
      }
    } else {
      if (isPositive) {
        // foo from hosted is a subset of not foo from git
        if (!_compatiblePackage(other.package)) return SetRelation.subset;

        // foo ^2.0.0 is a subset of not foo ^1.0.0
        if (!otherConstraint.allowsAny(constraint)) return SetRelation.subset;

        // foo ^1.5.0 is disjoint with not foo ^1.0.0
        if (otherConstraint.allowsAll(constraint)) return SetRelation.disjoint;

        // foo ^1.0.0 overlaps not foo ^1.5.0
        return SetRelation.overlapping;
      } else {
        // not foo from hosted overlaps not foo from git
        if (!_compatiblePackage(other.package)) return SetRelation.overlapping;

        // not foo ^1.0.0 is a subset of not foo ^1.5.0
        if (constraint.allowsAll(otherConstraint)) return SetRelation.subset;

        // not foo ^2.0.0 overlaps not foo ^1.0.0
        // not foo ^1.5.0 is a superset of not foo ^1.0.0
        return SetRelation.overlapping;
      }
    }
  }

  /// Returns a [Term] that represents the packages allowed by both [this] and
  /// [other].
  ///
  /// If there is no such single [Term], for example because [this] is
  /// incompatible with [other], returns `null`.
  ///
  /// Throws an [ArgumentError] if [other] doesn't refer to a package with the
  /// same name as [package].
  Term intersect(Term other) {
    if (package.name != other.package.name) {
      throw ArgumentError.value(
          other, 'other', 'should refer to package ${package.name}');
    }

    if (_compatiblePackage(other.package)) {
      if (isPositive != other.isPositive) {
        // foo ^1.0.0 ∩ not foo ^1.5.0 → foo >=1.0.0 <1.5.0
        var positive = isPositive ? this : other;
        var negative = isPositive ? other : this;
        return _nonEmptyTerm(
            positive.constraint.difference(negative.constraint), true);
      } else if (isPositive) {
        // foo ^1.0.0 ∩ foo >=1.5.0 <3.0.0 → foo ^1.5.0
        return _nonEmptyTerm(constraint.intersect(other.constraint), true);
      } else {
        // not foo ^1.0.0 ∩ not foo >=1.5.0 <3.0.0 → not foo >=1.0.0 <3.0.0
        return _nonEmptyTerm(constraint.union(other.constraint), false);
      }
    } else if (isPositive != other.isPositive) {
      // foo from git ∩ not foo from hosted → foo from git
      return isPositive ? this : other;
    } else {
      //     foo from git ∩     foo from hosted → empty
      // not foo from git ∩ not foo from hosted → no single term
      return null;
    }
  }

  /// Returns a [Term] that represents packages allowed by [this] and not by
  /// [other].
  ///
  /// If there is no such single [Term], for example because all packages
  /// allowed by [this] are allowed by [other], returns `null`.
  ///
  /// Throws an [ArgumentError] if [other] doesn't refer to a package with the
  /// same name as [package].
  Term difference(Term other) => intersect(other.inverse); // A ∖ B → A ∩ not B

  /// Returns whether [other] is compatible with [package].
  bool _compatiblePackage(PackageRange other) =>
      package.isRoot || other.isRoot || other.samePackage(package);

  /// Returns a new [Term] with the same package as [this] and with
  /// [constraint], unless that would produce a term that allows no packages,
  /// in which case this returns `null`.
  Term _nonEmptyTerm(VersionConstraint constraint, bool isPositive) =>
      constraint.isEmpty
          ? null
          : Term(package.withConstraint(constraint), isPositive);

  @override
  String toString() => "${isPositive ? '' : 'not '}$package";
}
