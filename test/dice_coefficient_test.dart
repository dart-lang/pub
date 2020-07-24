// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/dice_coefficient.dart';
import 'package:test/test.dart';

void main() {
  test('"" vs ""', () {
    expect(diceCoefficient('', ''), equals(1.0));
  });

  test('"" vs "a"', () {
    expect(diceCoefficient('', 'a'), equals(0.0));
  });

  test('"a" vs "a"', () {
    expect(diceCoefficient('a', 'a'), equals(1.0));
  });

  test('"a" vs "b"', () {
    expect(diceCoefficient('a', 'b'), equals(0.0));
  });

  test('"aa" vs "aaa"', () {
    expect(diceCoefficient('aa', 'aaa'), equals(2 / 3));
  });

  test('"aaaa" vs "aaaaa"', () {
    expect(diceCoefficient('aaaa', 'aaaaa'), equals(6 / 7));
  });

  test('"string" vs "nacht"', () {
    expect(diceCoefficient('string', 'nacht'), equals(0.0));
  });

  test('"night" vs "nacht"', () {
    expect(diceCoefficient('night', 'nacht'), equals(0.25));
  });

  test('"hello, world" vs "world, hello"', () {
    expect(diceCoefficient('hello, world', 'world, hello'), equals(9 / 11));
  });

  test('"dev_dependencies" vs "dev-dependencies"', () {
    expect(diceCoefficient('dev_dependencies', 'dev-dependencies'),
        equals(13 / 15));
  });

  test('"dependency" vs "dependencies"', () {
    expect(diceCoefficient('dependency', 'dependencies'), equals(0.8));
  });
}
