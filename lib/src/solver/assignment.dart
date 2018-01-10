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

  Assignment(
      PackageName package, bool isPositive, this.decisionLevel, this.index,
      {this.cause})
      : super(package, isPositive);
}
