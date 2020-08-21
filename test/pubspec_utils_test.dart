// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/pubspec_utils.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('stripUpperBound', () {
    test('works on version range', () {
      final constraint = VersionConstraint.parse('>=1.0.0 <3.0.0');
      final removedUpperBound = stripUpperBound(constraint) as VersionRange;

      expect(removedUpperBound.min, equals(Version(1, 0, 0)));
      expect(removedUpperBound.includeMin, isTrue);
      expect(removedUpperBound.max, isNull);
    });

    test('works on version range exclude min', () {
      final constraint = VersionConstraint.parse('>0.0.1 <5.0.0');
      final removedUpperBound = stripUpperBound(constraint) as VersionRange;

      expect(removedUpperBound.min, equals(Version(0, 0, 1)));
      expect(removedUpperBound.includeMin, isFalse);
      expect(removedUpperBound.max, isNull);
    });

    test('works on specific version constraint', () {
      final constraint = VersionConstraint.parse('1.2.3');
      final removedUpperBound = stripUpperBound(constraint) as VersionRange;

      expect(removedUpperBound.min, equals(Version(1, 2, 3)));
      expect(removedUpperBound.includeMin, isTrue);
      expect(removedUpperBound.max, isNull);
    });

    test('works on compatible version constraint', () {
      final constraint = VersionConstraint.parse('^1.2.3');
      final removedUpperBound = stripUpperBound(constraint) as VersionRange;

      expect(removedUpperBound.min, equals(Version(1, 2, 3)));
      expect(removedUpperBound.includeMin, isTrue);
      expect(removedUpperBound.max, isNull);
    });

    test('works on compatible version union', () {
      final constraint1 = VersionConstraint.parse('>=1.2.3 <2.0.0');
      final constraint2 = VersionConstraint.parse('>2.2.3 <=4.0.0');
      final constraint = VersionUnion.fromRanges([constraint1, constraint2]);

      final removedUpperBound = stripUpperBound(constraint) as VersionRange;

      expect(removedUpperBound.min, equals(Version(1, 2, 3)));
      expect(removedUpperBound.includeMin, isTrue);
      expect(removedUpperBound.max, isNull);
    });

    test(
        'returns the empty version constraint when an empty version constraint '
        'is provided', () {
      final constraint = VersionConstraint.empty;

      expect(stripUpperBound(constraint), VersionConstraint.empty);
    });

    test('returns the empty version constraint on empty version union', () {
      final constraint = VersionUnion.fromRanges([]);
      expect(stripUpperBound(constraint), VersionConstraint.empty);
    });
  });
}
