// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('throws PathError', () {
    test('if it is a map', () {
      final doc = YamlEditor('a:1');
      expect(() => doc.appendToList([], 4), throwsPathError);
    });

    test('if it is a scalar', () {
      final doc = YamlEditor('1');
      expect(() => doc.appendToList([], 4), throwsPathError);
    });
  });

  group('block list', () {
    test('(1)', () {
      final doc = YamlEditor('''
- 0
- 1
- 2
- 3
''');
      doc.appendToList([], 4);
      expect(doc.toString(), equals('''
- 0
- 1
- 2
- 3
- 4
'''));
      expectYamlBuilderValue(doc, [0, 1, 2, 3, 4]);
    });

    test('element to simple block list ', () {
      final doc = YamlEditor('''
- 0
- 1
- 2
- 3
''');
      doc.appendToList([], [4, 5, 6]);
      expect(doc.toString(), equals('''
- 0
- 1
- 2
- 3
- - 4
  - 5
  - 6
'''));
      expectYamlBuilderValue(doc, [
        0,
        1,
        2,
        3,
        [4, 5, 6]
      ]);
    });

    test('nested', () {
      final doc = YamlEditor('''
- 0
- - 1
  - 2
''');
      doc.appendToList([1], 3);
      expect(doc.toString(), equals('''
- 0
- - 1
  - 2
  - 3
'''));
      expectYamlBuilderValue(doc, [
        0,
        [1, 2, 3]
      ]);
    });

    test('block list element to nested block list ', () {
      final doc = YamlEditor('''
- 0
- - 1
  - 2
''');
      doc.appendToList([1], [3, 4, 5]);

      expect(doc.toString(), equals('''
- 0
- - 1
  - 2
  - - 3
    - 4
    - 5
'''));
      expectYamlBuilderValue(doc, [
        0,
        [
          1,
          2,
          [3, 4, 5]
        ]
      ]);
    });
  });

  group('flow list', () {
    test('(1)', () {
      final doc = YamlEditor('[0, 1, 2]');
      doc.appendToList([], 3);
      expect(doc.toString(), equals('[0, 1, 2, 3]'));
      expectYamlBuilderValue(doc, [0, 1, 2, 3]);
    });

    test('empty ', () {
      final doc = YamlEditor('[]');
      doc.appendToList([], 0);
      expect(doc.toString(), equals('[0]'));
      expectYamlBuilderValue(doc, [0]);
    });
  });
}
