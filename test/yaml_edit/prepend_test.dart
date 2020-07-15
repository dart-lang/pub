// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  group('throws PathError', () {
    test('if it is a map', () {
      final doc = YamlEditor('a:1');
      expect(() => doc.prependToList([], 4), throwsPathError);
    });

    test('if it is a scalar', () {
      final doc = YamlEditor('1');
      expect(() => doc.prependToList([], 4), throwsPathError);
    });
  });

  group('flow list', () {
    test('(1)', () {
      final doc = YamlEditor('[1, 2]');
      doc.prependToList([], 0);
      expect(doc.toString(), equals('[0, 1, 2]'));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });

    test('with spaces (1)', () {
      final doc = YamlEditor('[ 1 , 2 ]');
      doc.prependToList([], 0);
      expect(doc.toString(), equals('[ 0, 1 , 2 ]'));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });
  });

  group('block list', () {
    test('(1)', () {
      final doc = YamlEditor('''
- 1
- 2''');
      doc.prependToList([], 0);
      expect(doc.toString(), equals('''
- 0
- 1
- 2'''));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });

    /// Regression testing for no trailing spaces.
    test('(2)', () {
      final doc = YamlEditor('''- 1
- 2''');
      doc.prependToList([], 0);
      expect(doc.toString(), equals('''- 0
- 1
- 2'''));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });

    test('(3)', () {
      final doc = YamlEditor('''
- 1
- 2
''');
      doc.prependToList([], [4, 5, 6]);
      expect(doc.toString(), equals('''
- - 4
  - 5
  - 6
- 1
- 2
'''));
      expectYamlBuilderValue(doc, [
        [4, 5, 6],
        1,
        2
      ]);
    });

    test('(4)', () {
      final doc = YamlEditor('''
a:
 - b
 - - c
   - d
''');
      doc.prependToList(
          ['a'], wrapAsYamlNode({1: 2}, collectionStyle: CollectionStyle.FLOW));

      expect(doc.toString(), equals('''
a:
 - {1: 2}
 - b
 - - c
   - d
'''));
      expectYamlBuilderValue(doc, {
        'a': [
          {1: 2},
          'b',
          ['c', 'd']
        ]
      });
    });

    test('with comments ', () {
      final doc = YamlEditor('''
# comments
- 1 # comments
- 2
''');
      doc.prependToList([], 0);
      expect(doc.toString(), equals('''
# comments
- 0
- 1 # comments
- 2
'''));
      expectYamlBuilderValue(doc, [0, 1, 2]);
    });

    test('nested in map', () {
      final doc = YamlEditor('''
a:
  - 1
  - 2
''');
      doc.prependToList(['a'], 0);
      expect(doc.toString(), equals('''
a:
  - 0
  - 1
  - 2
'''));
      expectYamlBuilderValue(doc, {
        'a': [0, 1, 2]
      });
    });

    test('nested in map with comments ', () {
      final doc = YamlEditor('''
a: # comments
  - 1 # comments
  - 2
''');
      doc.prependToList(['a'], 0);
      expect(doc.toString(), equals('''
a: # comments
  - 0
  - 1 # comments
  - 2
'''));
      expectYamlBuilderValue(doc, {
        'a': [0, 1, 2]
      });
    });
  });
}
