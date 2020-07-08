// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('windows line ending detection', () {
    test('empty string gives not windows', () {
      final doc = YamlEditor('');
      expect(doc.lineEnding, equals('\n'));
    });

    test('accurately detects windows documents', () {
      final doc = YamlEditor('\r\n');
      expect(doc.lineEnding, equals('\r\n'));
    });

    test('accurately detects windows documents (2)', () {
      final doc = YamlEditor('''
a:\r
  b:\r
    - 1\r
    - 2\r
c: 3\r
''');
      expect(doc.lineEnding, equals('\r\n'));
    });
  });

  group('modification with windows line endings', () {
    test('append element to simple block list ', () {
      final doc = YamlEditor('''
- 0\r
- 1\r
- 2\r
- 3\r
''');
      doc.appendToList([], [4, 5, 6]);
      expect(doc.toString(), equals('''
- 0\r
- 1\r
- 2\r
- 3\r
- - 4\r
  - 5\r
  - 6\r
'''));
      expectYamlBuilderValue(doc, [
        0,
        1,
        2,
        3,
        [4, 5, 6]
      ]);
    });

    test('update nested scalar -> flow list', () {
      final doc = YamlEditor('''
a: 1\r
b: \r
  d: 4\r
  e: 5\r
c: 3\r
''');
      doc.update(['b', 'e'], [1, 2, 3]);

      expect(doc.toString(), equals('''
a: 1\r
b: \r
  d: 4\r
  e: \r
    - 1\r
    - 2\r
    - 3\r
c: 3\r
'''));
      expectYamlBuilderValue(doc, {
        'a': 1,
        'b': {
          'd': 4,
          'e': [1, 2, 3]
        },
        'c': 3
      });
    });

    test('update in nested list flow map -> scalar', () {
      final doc = YamlEditor('''
- 0\r
- {a: 1, b: 2}\r
- 2\r
- 3\r
''');
      doc.update([1], 4);
      expect(doc.toString(), equals('''
- 0\r
- 4\r
- 2\r
- 3\r
'''));
      expectYamlBuilderValue(doc, [0, 4, 2, 3]);
    });

    test('insert into a list with comments', () {
      final doc = YamlEditor('''
- 0 # comment a\r
- 2 # comment b\r
''');
      doc.insertIntoList([], 1, 1);
      expect(doc.toString(), equals('''
- 0 # comment a\r
- 1\r
- 2 # comment b\r
'''));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });

    test('prepend into a list', () {
      final doc = YamlEditor('''
- 1\r
- 2\r
''');
      doc.prependToList([], [4, 5, 6]);
      expect(doc.toString(), equals('''
- - 4\r
  - 5\r
  - 6\r
- 1\r
- 2\r
'''));
      expectYamlBuilderValue(doc, [
        [4, 5, 6],
        1,
        2
      ]);
    });

    test('remove from block list ', () {
      final doc = YamlEditor('''
- 0\r
- 1\r
- 2\r
- 3\r
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0\r
- 2\r
- 3\r
'''));
      expectYamlBuilderValue(doc, [0, 2, 3]);
    });

    test('remove from block list (2)', () {
      final doc = YamlEditor('''
- 0\r
''');
      doc.remove([0]);
      expect(doc.toString(), equals('''
[]\r
'''));
      expectYamlBuilderValue(doc, []);
    });

    test('remove from block map', () {
      final doc = YamlEditor('''
a: 1\r
b: 2\r
c: 3\r
''');
      doc.remove(['b']);
      expect(doc.toString(), equals('''
a: 1\r
c: 3\r
'''));
    });

    test('remove from block map (2)', () {
      final doc = YamlEditor('''
a: 1\r
''');
      doc.remove(['a']);
      expect(doc.toString(), equals('''
{}\r
'''));
      expectYamlBuilderValue(doc, {});
    });

    test('splice block list', () {
      final doc = YamlEditor('''
- 0\r
- 0\r
''');
      final nodes = doc.spliceList([], 0, 2, [0, 1, 2]);
      expect(doc.toString(), equals('''
- 0\r
- 1\r
- 2\r
'''));

      expectDeepEquals(nodes.toList(), [0, 0]);
    });
  });
}
