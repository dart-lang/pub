// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';
import 'incompatibility_cause.dart';
import 'term.dart';

/// A set of mutually-incompatible terms.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#incompatibility.
class Incompatibility {
  /// The mutually-incompatibile terms.
  final List<Term> terms;

  /// The reason [terms] are incompatible.
  final IncompatibilityCause cause;

  /// Whether this incompatibility indicates that version solving as a whole has
  /// failed.
  bool get isFailure => terms.length == 1 && terms.first.package.isRoot;

  /// Creates an incompatibility with [terms].
  ///
  /// This normalizes [terms] so that each package has at most one term
  /// referring to it.
  factory Incompatibility(List<Term> terms, IncompatibilityCause cause) {
    if (terms.length == 1 ||
        // Short-circuit in the common case of a two-term incompatibility with
        // two different packages (for example, a dependency).
        (terms.length == 2 &&
            terms.first.package.name != terms.last.package.name)) {
      return new Incompatibility._(terms, cause);
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

    return new Incompatibility._(
        byName.values.expand((byRef) {
          // If there are any positive terms for a given package, we can discard
          // any negative terms.
          var positiveTerms =
              byRef.values.where((term) => term.isPositive).toList();
          if (positiveTerms.isNotEmpty) return positiveTerms;

          return byRef.values;
        }).toList(),
        cause);
  }

  Incompatibility._(this.terms, this.cause);

  String toString() {
    if (cause == IncompatibilityCause.dependency) {
      assert(terms.length == 2);

      var depender = terms.first;
      var dependee = terms.last;
      assert(depender.isPositive);
      assert(!dependee.isPositive);

      if (depender.constraint.isAny) {
        return "all versions of ${_terseRef(depender)} "
            "depend on ${dependee.package.toTerseString()}";
      } else {
        return "${depender.package.toTerseString()} depends on "
            "${dependee.package.toTerseString()}";
      }
    } else if (cause == IncompatibilityCause.sdk) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);

      // TODO(nweiz): Include more details about the expected and actual SDK
      // versions.
      if (terms.first.constraint.isAny) {
        return "no versions of ${_terseRef(terms.first)} "
            "are compatible with the current SDK";
      } else {
        return "${terms.first.package.toTerseString()} is incompatible with "
            "the current SDK";
      }
    } else if (cause == IncompatibilityCause.noVersions) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);
      return "no versions of ${_terseRef(terms.first)} "
          "match ${terms.first.constraint}";
    } else if (isFailure) {
      return "version solving failed";
    }

    if (terms.length == 1) {
      var term = terms.single;
      if (term.constraint.isAny) {
        return "${_terseRef(term)} is "
            "${term.isPositive ? 'forbidden' : 'required'}";
      } else {
        return "${term.package.toTerseString()} is "
            "${term.isPositive ? 'forbidden' : 'required'}";
      }
    }

    if (terms.length == 2) {
      var term1 = terms.first;
      var term2 = terms.last;
      if (term1.isPositive == term2.isPositive) {
        if (term1.isPositive) {
          var package1 = term1.constraint.isAny
              ? _terseRef(term1)
              : term1.package.toTerseString();
          var package2 = term2.constraint.isAny
              ? _terseRef(term2)
              : term2.package.toTerseString();
          return "$package1 is incompatible with $package2";
        } else {
          return "either ${term1.package.toTerseString()} or "
              "${term2.package.toTerseString()}";
        }
      }
    }

    var positive = <String>[];
    var negative = <String>[];
    for (var term in terms) {
      (term.isPositive ? positive : negative).add(term.package.toTerseString());
    }

    if (positive.isNotEmpty && negative.isNotEmpty) {
      if (positive.length == 1) {
        var positiveTerm = terms.firstWhere((term) => term.isPositive);
        if (positiveTerm.constraint.isAny) {
          return "all versions of ${_terseRef(positiveTerm)} require "
              "${negative.join(' or ')}";
        } else {
          return "${positive.first} requires ${negative.join(' or ')}";
        }
      } else {
        return "if ${positive.join(' and ')} then ${negative.join(' or ')}";
      }
    } else if (positive.isNotEmpty) {
      return "one of ${positive.join(' or ')} must be false";
    } else {
      return "one of ${negative.join(' or ')} must be true";
    }
  }

  /// Returns a terse representation of term's package ref.
  String _terseRef(Term term) => term.package.toRef().toTerseString();
}
