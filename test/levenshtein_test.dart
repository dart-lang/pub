// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/levenshtein.dart';
import 'package:test/test.dart';

void main() {
  test('"" vs ""', () {
    expect(levenshteinDistance('', ''), 0);
  });

  test('"" vs "a"', () {
    expect(levenshteinDistance('', 'a'), 1);
  });

  test('"a" vs "a"', () {
    expect(levenshteinDistance('a', 'a'), 0);
  });

  test('"a" vs "b"', () {
    expect(levenshteinDistance('a', 'b'), 1);
  });

  test('"aa" vs "aaa"', () {
    expect(levenshteinDistance('aa', 'aaa'), 1);
  });

  test('"aaaa" vs "aaaaa"', () {
    expect(levenshteinDistance('aaaa', 'aaaaa'), 1);
  });

  test('"string" vs "nacht"', () {
    expect(levenshteinDistance('string', 'nacht'), 6);
  });

  test('"night" vs "nacht"', () {
    expect(levenshteinDistance('night', 'nacht'), 2);
  });

  test('"hello, world" vs "world, hello"', () {
    expect(levenshteinDistance('hello, world', 'world, hello'), 8);
  });

  test('"dev_dependencies" vs "dev-dependencies"', () {
    expect(levenshteinDistance('dev_dependencies', 'dev-dependencies'), 1);
  });

  test('"dependency" vs "dependencies"', () {
    expect(levenshteinDistance('dependency', 'dependencies'), 3);
  });

  test('is symmetrical', () {
    expect(levenshteinDistance('j', 'alsdlasksjdlakdjlakq2rqb1o3i'),
        levenshteinDistance('alsdlasksjdlakdjlakq2rqb1o3i', 'j'));
  });
}
