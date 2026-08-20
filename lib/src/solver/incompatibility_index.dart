// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'incompatibility.dart';
import 'partial_solution.dart';
import 'set_relation.dart';

/// An index of incompatibilities optimized for fast unit propagation in the
/// version solver.
///
/// In PubGrub, most incompatibilities are binary dependencies (e.g.
/// `{foo ^1.0.0, not bar ^2.0.0}`). This index optimizes binary clause
/// evaluation during unit propagation while preserving exact PubGrub
/// resolution semantics and reverse-chronological clause ordering.
class IncompatibilityIndex {
  /// All incompatibilities indexed by package name.
  final _incompatibilities = <String, List<Incompatibility>>{};

  /// Adds [incompatibility] to the index for each package it refers to.
  void add(Incompatibility incompatibility) {
    for (final term in incompatibility.terms) {
      _incompatibilities
          .putIfAbsent(term.package.name, () => [])
          .add(incompatibility);
    }
  }

  /// Iterates in reverse chronological order over incompatibilities associated
  /// with [package].
  ///
  /// For binary incompatibilities, quickly skips clauses where neither term is
  /// satisfied by [solution].
  ///
  /// Calls [action] for each candidate clause. If [action] returns `false`,
  /// iteration stops immediately (e.g. on conflict).
  void forEachCandidate(
    String package,
    PartialSolution solution,
    bool Function(Incompatibility) action,
  ) {
    final list = _incompatibilities[package];
    if (list == null) return;

    for (var i = list.length - 1; i >= 0; i--) {
      final incomp = list[i];
      final terms = incomp.terms;

      // Fast-skip binary clauses where neither term is satisfied.
      if (terms.length == 2) {
        final t0 = terms[0];
        final t1 = terms[1];

        // If neither term's package is assigned or neither is subset, skip.
        final rel0 = solution.relation(t0);
        if (rel0 == SetRelation.disjoint) continue;

        final rel1 = solution.relation(t1);
        if (rel1 == SetRelation.disjoint) continue;

        if (rel0 != SetRelation.subset && rel1 != SetRelation.subset) {
          // Both terms are overlapping (inconclusive); no derivation possible.
          continue;
        }
      }

      if (!action(incomp)) break;
    }
  }
}
