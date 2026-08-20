// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/incompatibility.dart';
import 'package:pub/src/solver/incompatibility_cause.dart';
import 'package:pub/src/solver/incompatibility_index.dart';
import 'package:pub/src/solver/partial_solution.dart';
import 'package:pub/src/solver/term.dart';
import 'package:pub/src/source/root.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  PackageRange range(String name, [String constraint = 'any']) {
    return PackageRange(
      PackageRef(name, RootDescription('.')),
      VersionConstraint.parse(constraint),
    );
  }

  Incompatibility binary(PackageRange r1, PackageRange r2) {
    return Incompatibility([
      Term(r1, true),
      Term(r2, false),
    ], RootIncompatibilityCause());
  }

  Incompatibility unary(PackageRange r) {
    return Incompatibility([Term(r, true)], RootIncompatibilityCause());
  }

  Incompatibility nary(List<PackageRange> ranges) {
    return Incompatibility(
      ranges.map((r) => Term(r, true)).toList(),
      RootIncompatibilityCause(),
    );
  }

  group('IncompatibilityIndex', () {
    late IncompatibilityIndex index;
    late PartialSolution solution;

    setUp(() {
      index = IncompatibilityIndex();
      solution = PartialSolution({});
    });

    test('retrieves unary incompatibilities in reverse order', () {
      final incomp1 = unary(range('foo', '1.0.0'));
      final incomp2 = unary(range('foo', '2.0.0'));

      index.add(incomp1);
      index.add(incomp2);

      final candidates = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidates.add(incomp);
        return true;
      });

      expect(candidates, equals([incomp2, incomp1]));
    });

    test('skips binary clause when neither term is satisfied', () {
      final incomp = binary(range('foo', '1.0.0'), range('bar', '2.0.0'));
      index.add(incomp);

      final candidatesFoo = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidatesFoo.add(incomp);
        return true;
      });
      expect(candidatesFoo, isEmpty);

      final candidatesBar = <Incompatibility>[];
      index.forEachCandidate('bar', solution, (incomp) {
        candidatesBar.add(incomp);
        return true;
      });
      expect(candidatesBar, isEmpty);
    });

    test('yields binary clause when self term is satisfied', () {
      final incomp = binary(range('foo', '1.0.0'), range('bar', '2.0.0'));
      index.add(incomp);

      solution.derive(
        range('foo', '1.0.0'),
        true,
        Incompatibility([], RootIncompatibilityCause()),
      );

      final candidatesFoo = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidatesFoo.add(incomp);
        return true;
      });
      expect(candidatesFoo, equals([incomp]));
    });

    test('yields binary clause when other term is satisfied', () {
      final incomp = binary(range('foo', '1.0.0'), range('bar', '2.0.0'));
      index.add(incomp);

      // Derive 'not bar 2.0.0' which satisfies 'Term(bar 2.0.0, false)'
      solution.derive(
        range('bar', '2.0.0'),
        false,
        Incompatibility([], RootIncompatibilityCause()),
      );

      final candidatesFoo = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidatesFoo.add(incomp);
        return true;
      });
      expect(candidatesFoo, equals([incomp]));
    });

    test('skips binary clause when a term is contradicted (disjoint)', () {
      final incomp = binary(range('foo', '1.0.0'), range('bar', '2.0.0'));
      index.add(incomp);

      // Derive 'not foo 1.0.0', contradicting 'Term(foo 1.0.0, true)'
      solution.derive(
        range('foo', '1.0.0'),
        false,
        Incompatibility([], RootIncompatibilityCause()),
      );

      final candidatesFoo = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidatesFoo.add(incomp);
        return true;
      });
      expect(candidatesFoo, isEmpty);
    });

    test('handles n-ary clauses for all referenced packages', () {
      final incomp = nary([
        range('foo', '1.0.0'),
        range('bar', '2.0.0'),
        range('baz', '3.0.0'),
      ]);
      index.add(incomp);

      for (final pkg in ['foo', 'bar', 'baz']) {
        final candidates = <Incompatibility>[];
        index.forEachCandidate(pkg, solution, (incomp) {
          candidates.add(incomp);
          return true;
        });
        expect(candidates, equals([incomp]));
      }
    });

    test('stops iteration when callback returns false', () {
      final incomp1 = unary(range('foo', '1.0.0'));
      final incomp2 = unary(range('foo', '2.0.0'));
      index.add(incomp1);
      index.add(incomp2);

      final candidates = <Incompatibility>[];
      index.forEachCandidate('foo', solution, (incomp) {
        candidates.add(incomp);
        return false; // Stop after first
      });

      expect(candidates, equals([incomp2]));
    });
  });
}
