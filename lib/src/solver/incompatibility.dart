// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';
import 'term.dart';

/// A set of mutually-incompatible terms.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#incompatibility.
class Incompatibility {
  /// The mutually-incompatibile terms.
  final List<Term> terms;

  /// Creates an incompatibility with [terms].
  ///
  /// This normalizes [terms] so that each package has at most one term
  /// referring to it.
  factory Incompatibility(List<Term> terms) {
    if (terms.length == 1 ||
        // Short-circuit in the common case of a two-term incompatibility with
        // two different packages (for example, a dependency).
        (terms.length == 2 &&
            terms.first.package.name != terms.last.package.name)) {
      return new Incompatibility._(terms);
    }

    // Coalesce multiple terms about the same package if possible.
    var byName = <String, Map<PackageRef, Term>>{};
    for (var term in terms) {
      var byRef = byName.putIfAbsent(term.package.name, () => {});
      var ref = term.package.toRef();
      if (byRef.containsKey(ref)) {
        byRef[ref] = byRef[ref].intersect(term);

        // If we have two terms that refer to the same package but have a null
        // intersection, they're mutually exclusive, making this incompatibility
        // irrelevant, since we already know that mutually exclusive version
        // ranges are incompatible. We should never derive an irrelevant
        // incompatibility.
        assert(byRef[ref] != null);
      } else {
        byRef[ref] = term;
      }
    }

    return new Incompatibility._(byName.values.expand((byRef) {
      // If there are any positive terms for a given package, we can discard
      // any negative terms.
      var positiveTerms =
          byRef.values.where((term) => term.isPositive).toList();
      if (positiveTerms.isNotEmpty) return positiveTerms;

      return byRef.values;
    }).toList());
  }

  Incompatibility._(this.terms);

  String toString() {
    if (terms.length == 1) {
      var term = terms.single;
      return "${term.package.toTerseString()} is "
          "${term.isPositive ? 'forbidden' : 'required'}";
    }

    if (terms.length == 2) {
      var term1 = terms.first;
      var term2 = terms.last;
      if (term1.isPositive != term2.isPositive) {
        var positive = (term1.isPositive ? term1 : term2).package;
        var negative = (term1.isPositive ? term2 : term1).package;
        return "if ${positive.toTerseString()} then ${negative.toTerseString()}";
      } else if (term1.isPositive) {
        return "${term1.package.toTerseString()} is incompatible with "
            "${term2.package.toTerseString()}";
      } else {
        return "either ${term1.package.toTerseString()} or "
            "${term2.package.toTerseString()}";
      }
    }

    var positive = <String>[];
    var negative = <String>[];
    for (var term in terms) {
      (term.isPositive ? positive : negative).add(term.package.toTerseString());
    }

    if (positive.isNotEmpty && negative.isNotEmpty) {
      return "if ${positive.join(' and ')} then ${negative.join(' and ')}";
    } else if (positive.isNotEmpty) {
      return "one of ${positive.join(' or ')} must be false";
    } else {
      return "one of ${negative.join(' or ')} must be true";
    }
  }
}
