// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/incompatibility.dart';
import 'package:pub/src/solver/incompatibility_cause.dart';
import 'package:pub/src/solver/incompatibility_index.dart';
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

    setUp(() {
      index = IncompatibilityIndex();
    });

    test('returns empty iterable for unknown package', () {
      expect(index.forPackage('unknown'), isEmpty);
    });

    test('retrieves incompatibilities in reverse order', () {
      final incomp1 = unary(range('foo', '1.0.0'));
      final incomp2 = unary(range('foo', '2.0.0'));

      index.add(incomp1);
      index.add(incomp2);

      expect(index.forPackage('foo').toList(), equals([incomp2, incomp1]));
    });

    test('indexes binary incompatibilities under both packages', () {
      final incomp = binary(range('foo', '1.0.0'), range('bar', '2.0.0'));
      index.add(incomp);

      expect(index.forPackage('foo').toList(), equals([incomp]));
      expect(index.forPackage('bar').toList(), equals([incomp]));
    });

    test('indexes n-ary incompatibilities under all referenced packages', () {
      final incomp = nary([
        range('foo', '1.0.0'),
        range('bar', '2.0.0'),
        range('baz', '3.0.0'),
      ]);
      index.add(incomp);

      for (final pkg in ['foo', 'bar', 'baz']) {
        expect(index.forPackage(pkg).toList(), equals([incomp]));
      }
      expect(index.forPackage('qux'), isEmpty);
    });
  });
}
