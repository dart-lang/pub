// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/solver/bitmask.dart';
import 'package:test/test.dart';

void main() {
  for (final length in [0, 1, 5, 62, 63, 64, 65, 128, 256, 1000]) {
    group('Bitmask (length $length)', () {
      test('empty mask', () {
        final mask = Bitmask.empty(length);
        expect(mask.length, length);
        expect(mask.isEmpty, true);
        expect(mask.isNotEmpty, false);
        expect(mask.count(), 0);
        expect(mask.highestIndex(), -1);
        expect(mask.lowestIndex(), -1);
        expect(mask.allows(-1), false);
        expect(mask.allows(0), false);
        expect(mask.allows(length), false);
        expect(mask.allows(length + 10), false);
      });

      test('all mask', () {
        final mask = Bitmask.all(length);
        expect(mask.length, length);
        expect(mask.isEmpty, length == 0);
        expect(mask.count(), length);
        expect(mask.allows(-1), false);
        expect(mask.allows(length), false);
        if (length > 0) {
          expect(mask.highestIndex(), length - 1);
          expect(mask.lowestIndex(), 0);
          for (var i = 0; i < length; i++) {
            expect(mask.allows(i), true);
          }
        }
      });

      test('single mask bounds', () {
        final negMask = Bitmask.single(length, -1);
        expect(negMask.isEmpty, true);
        expect(negMask.count(), 0);

        final outMask = Bitmask.single(length, length);
        expect(outMask.isEmpty, true);
        expect(outMask.count(), 0);
      });

      if (length > 0) {
        test('single mask', () {
          final mask = Bitmask.single(length, length - 1);
          expect(mask.count(), 1);
          expect(mask.highestIndex(), length - 1);
          expect(mask.lowestIndex(), length - 1);
          expect(mask.allows(length - 1), true);
          expect(mask.allows(-1), false);
          expect(mask.allows(length), false);
          if (length > 1) {
            expect(mask.allows(0), false);
          }
        });

        test('range mask', () {
          final mid = length ~/ 2;
          final mask = Bitmask.range(length, 0, mid);
          expect(mask.count(), mid);
          if (mid > 0) {
            expect(mask.lowestIndex(), 0);
            expect(mask.highestIndex(), mid - 1);
            expect(mask.allows(0), true);
            expect(mask.allows(mid - 1), true);
          }
          if (mid < length) {
            expect(mask.allows(mid), false);
          }
        });

        test('fromPredicate mask', () {
          final evenMask = Bitmask.fromPredicate(length, (i) => i.isEven);
          for (var i = 0; i < length; i++) {
            expect(evenMask.allows(i), i.isEven);
          }
        });

        test('equality and hashCode', () {
          final mask1 = Bitmask.single(length, 0);
          final mask2 = Bitmask.single(length, 0);
          final mask3 = Bitmask.single(length, length - 1);

          expect(mask1, equals(mask2));
          expect(mask1.hashCode, equals(mask2.hashCode));
          if (length > 1) {
            expect(mask1, isNot(equals(mask3)));
          }
        });

        test('set operations (&, |, difference, allowsAll, allowsAny)', () {
          final mask1 = Bitmask.single(length, 0);
          final mask2 = Bitmask.single(length, length - 1);

          final union = mask1 | mask2;
          expect(union.allows(0), true);
          expect(union.allows(length - 1), true);
          expect(union.count(), length == 1 ? 1 : 2);

          final intersect = mask1 & mask2;
          if (length == 1) {
            expect(intersect.count(), 1);
            expect(mask1.allowsAll(mask2), true);
            expect(mask1.allowsAny(mask2), true);
          } else {
            expect(intersect.count(), 0);
            expect(intersect.isEmpty, true);
            expect(mask1.allowsAll(mask2), false);
            expect(mask1.allowsAny(mask2), false);
          }

          final diff = union.difference(mask1);
          if (length == 1) {
            expect(diff.isEmpty, true);
          } else {
            expect(diff.allows(length - 1), true);
            expect(diff.allows(0), false);
          }
        });
      }
    });
  }
}
