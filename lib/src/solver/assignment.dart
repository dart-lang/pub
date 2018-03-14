// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';
import 'incompatibility.dart';
import 'term.dart';

/// A term in a [PartialSolution] that tracks some additional metadata.
class Assignment extends Term {
  /// The number of decisions at or before this in the [PartialSolution] that
  /// contains it.
  final int decisionLevel;

  /// The index of this assignment in [PartialSolution.assignments].
  final int index;

  /// The incompatibility that caused this assignment to be derived, or `null`
  /// if the assignment isn't a derivation.
  final Incompatibility cause;

  /// The single package version selected by this assignment, or `null` if
  /// [isDecision] is `false`.
  final PackageId id;

  /// Whether this assignment is a decision to select a single package version.
  bool get isDecision => id != null;

  /// Creates a decision: a speculative assignment of a single package version.
  Assignment.decision(this.id, this.decisionLevel, this.index)
      : cause = null,
        super(id, true);

  /// Creates a derivation: an assignment that's automatically propagated from
  /// incompatibilities.
  Assignment.derivation(PackageName package, bool isPositive, this.cause,
      this.decisionLevel, this.index)
      : id = null,
        super(package, isPositive);
}
