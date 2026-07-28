// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/incompatibility.dart';
import 'package:pub/src/solver/incompatibility_cause.dart';
import 'package:pub/src/solver/partial_solution.dart';
import 'package:pub/src/solver/term.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/source/root.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  final firstVersion = Version(1, 0, 0);
  final secondVersion = Version(2, 0, 0);
  final firstRef = PackageRef(
    'foo',
    HostedDescription('foo', 'https://first.example'),
  );
  final secondRef = PackageRef(
    'foo',
    HostedDescription('foo', 'https://second.example'),
  );
  final rootRef = PackageRef('foo', RootDescription('/workspace/foo'));
  final cause = Incompatibility([
    Term(rootRef.withConstraint(VersionConstraint.any), true),
  ], NoVersionsIncompatibilityCause());

  PartialSolution solutionFor(Iterable<Term> terms) {
    final solution = PartialSolution({'foo': rootRef});
    for (final term in terms) {
      solution.derive(term.package, term.isPositive, cause);
    }
    return solution;
  }

  test('finds satisfiers across root-compatible source references', () {
    final firstNegative = Term(firstRef.withConstraint(firstVersion), false);
    final secondNegative = Term(secondRef.withConstraint(secondVersion), false);
    final rootNegative = Term(
      rootRef.withConstraint(firstVersion.union(secondVersion)),
      false,
    );

    for (final terms in [
      [firstNegative, secondNegative],
      [secondNegative, firstNegative],
    ]) {
      final solution = solutionFor(terms);

      expect(solution.satisfies(rootNegative), isTrue);
      expect(solution.satisfier(rootNegative).index, 1);
    }
  });

  test('keeps ordinary source references separate', () {
    final solution = PartialSolution();
    final firstNegative = Term(firstRef.withConstraint(firstVersion), false);
    final secondNegative = Term(secondRef.withConstraint(secondVersion), false);

    solution.derive(firstNegative.package, false, cause);
    solution.derive(secondNegative.package, false, cause);

    expect(solution.satisfies(firstNegative), isTrue);
    expect(solution.satisfies(secondNegative), isTrue);
    expect(
      solution.satisfies(Term(firstRef.withConstraint(secondVersion), false)),
      isFalse,
    );
    expect(
      solution.satisfies(Term(secondRef.withConstraint(firstVersion), false)),
      isFalse,
    );
  });

  test('applies root negatives regardless of assignment order', () {
    final rootNegative = Term(rootRef.withConstraint(firstVersion), false);
    final positive = Term(firstRef.withConstraint(VersionConstraint.any), true);
    final firstNegative = Term(firstRef.withConstraint(firstVersion), false);

    for (final terms in [
      [rootNegative, positive],
      [positive, rootNegative],
    ]) {
      final solution = solutionFor(terms);

      expect(solution.satisfies(firstNegative), isTrue);
    }
  });

  test('preserves root projections when positive references mix', () {
    final rootPositive = Term(
      rootRef.withConstraint(VersionConstraint.any),
      true,
    );
    final firstPositive = Term(
      firstRef.withConstraint(VersionConstraint.any),
      true,
    );
    final secondNegative = Term(secondRef.withConstraint(secondVersion), false);
    final rootNegative = Term(rootRef.withConstraint(secondVersion), false);

    final rootSolution = solutionFor([rootPositive, secondNegative]);
    expect(rootSolution.satisfies(rootNegative), isTrue);
    expect(rootSolution.satisfier(rootNegative).index, 1);

    final rootFirst = solutionFor([
      rootPositive,
      secondNegative,
      firstPositive,
    ]);
    expect(rootFirst.satisfies(rootNegative), isTrue);
    expect(rootFirst.satisfier(rootNegative).index, 1);

    final rootLast = solutionFor([firstPositive, secondNegative, rootPositive]);
    expect(rootLast.satisfies(rootNegative), isTrue);
    expect(rootLast.satisfier(rootNegative).index, 1);
  });
}
