// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'incompatibility.dart';

/// An index of incompatibilities optimized for unit propagation in the
/// version solver.
///
/// Incompatibilities are indexed by package name and iterated in
/// reverse-chronological order so that more recently learned conflict clauses
/// are evaluated first during propagation.
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

  /// Returns an iterable over incompatibilities associated with [package] in
  /// reverse-chronological order.
  Iterable<Incompatibility> forPackage(String package) {
    final list = _incompatibilities[package];
    if (list == null) return const [];
    return list.reversed;
  }
}
