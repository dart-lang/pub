// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('throws', () {
    test('PathError if collectionPath points to a scalar', () {
      final doc = YamlEditor('''
a: 1
b: 2
c: 3
''');

      expect(() => doc.remove(['a', 0]), throwsPathError);
    });

    test('PathError if collectionPath is invalid', () {
      final doc = YamlEditor('''
a: 1
b: 2
c: 3
''');

      expect(() => doc.remove(['d']), throwsPathError);
    });

    test('PathError if collectionPath is invalid - list', () {
      final doc = YamlEditor('''
[1, 2, 3]
''');

      expect(() => doc.remove([4]), throwsPathError);
    });
  });

  test('empty path should clear string', () {
    final doc = YamlEditor('''
a: 1
b: 2
c: [3, 4]
''');
    doc.remove([]);
    expect(doc.toString(), equals(''));
  });

  group('block map', () {
    test('(1)', () {
      final doc = YamlEditor('''
a: 1
b: 2
c: 3
''');
      doc.remove(['b']);
      expect(doc.toString(), equals('''
a: 1
c: 3
'''));
    });

    test('final element in map', () {
      final doc = YamlEditor('''
a: 1
b: 2
''');
      doc.remove(['b']);
      expect(doc.toString(), equals('''
a: 1
'''));
    });

    test('final element in nested map', () {
      final doc = YamlEditor('''
a: 
  aa: 11
  bb: 22
b: 2
''');
      doc.remove(['a', 'bb']);
      expect(doc.toString(), equals('''
a: 
  aa: 11
b: 2
'''));
    });

    test('last element should return flow empty map', () {
      final doc = YamlEditor('''
a: 1
''');
      doc.remove(['a']);
      expect(doc.toString(), equals('''
{}
'''));
    });

    test('last element should return flow empty map (2)', () {
      final doc = YamlEditor('''
- a: 1
- b: 2
''');
      doc.remove([0, 'a']);
      expect(doc.toString(), equals('''
- {}
- b: 2
'''));
    });

    test('nested', () {
      final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5
c: 3
''');
      doc.remove(['b', 'd']);
      expect(doc.toString(), equals('''
a: 1
b: 
  e: 5
c: 3
'''));
    });
  });

  group('block list', () {
    test('last element should return flow empty list', () {
      final doc = YamlEditor('''
- 0
''');
      doc.remove([0]);
      expect(doc.toString(), equals('''
[]
'''));
    });

    test('last element should return flow empty list (2)', () {
      final doc = YamlEditor('''
a: [1]
b: [3]
''');
      doc.remove(['a', 0]);
      expect(doc.toString(), equals('''
a: []
b: [3]
'''));
    });

    test('last element should return flow empty list (3)', () {
      final doc = YamlEditor('''
a: 
  - 1
b: 
  - 3
''');
      doc.remove(['a', 0]);
      expect(doc.toString(), equals('''
a: 
  []
b: 
  - 3
'''));
    });
  });

  group('flow map', () {
    test('(1)', () {
      final doc = YamlEditor('{a: 1, b: 2, c: 3}');
      doc.remove(['b']);
      expect(doc.toString(), equals('{a: 1, c: 3}'));
    });

    test('(2) ', () {
      final doc = YamlEditor('{a: 1}');
      doc.remove(['a']);
      expect(doc.toString(), equals('{}'));
    });

    test('(3) ', () {
      final doc = YamlEditor('{a: 1, b: 2}');
      doc.remove(['a']);
      expect(doc.toString(), equals('{ b: 2}'));
    });

    test('(4) ', () {
      final doc =
          YamlEditor('{"{}[],": {"{}[],": 1, b: "}{[]},", "}{[],": 3}}');
      doc.remove(['{}[],', 'b']);
      expect(doc.toString(), equals('{"{}[],": {"{}[],": 1, "}{[],": 3}}'));
    });

    test('nested flow map ', () {
      final doc = YamlEditor('{a: 1, b: {d: 4, e: 5}, c: 3}');
      doc.remove(['b', 'd']);
      expect(doc.toString(), equals('{a: 1, b: { e: 5}, c: 3}'));
    });

    test('nested flow map (2)', () {
      final doc = YamlEditor('{a: {{[1] : 2}: 3, b: 2}}');
      doc.remove([
        'a',
        {
          [1]: 2
        }
      ]);
      expect(doc.toString(), equals('{a: { b: 2}}'));
    });
  });

  group('block list', () {
    test('(1) ', () {
      final doc = YamlEditor('''
- 0
- 1
- 2
- 3
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0
- 2
- 3
'''));
      expectYamlBuilderValue(doc, [0, 2, 3]);
    });

    test('(2)', () {
      final doc = YamlEditor('''
- 0
- [1,2,3]
- 2
- 3
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0
- 2
- 3
'''));
      expectYamlBuilderValue(doc, [0, 2, 3]);
    });

    test('(3)', () {
      final doc = YamlEditor('''
- 0
- {a: 1, b: 2}
- 2
- 3
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0
- 2
- 3
'''));
      expectYamlBuilderValue(doc, [0, 2, 3]);
    });

    test('last element', () {
      final doc = YamlEditor('''
- 0
- 1
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0
'''));
      expectYamlBuilderValue(doc, [0]);
    });

    test('with comments', () {
      final doc = YamlEditor('''
- 0
- 1 # comments
- 2
- 3
''');
      doc.remove([1]);
      expect(doc.toString(), equals('''
- 0
- 2
- 3
'''));
      expectYamlBuilderValue(doc, [0, 2, 3]);
    });

    test('nested', () {
      final doc = YamlEditor('''
- - - 0
    - 1
''');
      doc.remove([0, 0, 0]);
      expect(doc.toString(), equals('''
- - - 1
'''));
      expectYamlBuilderValue(doc, [
        [
          [1]
        ]
      ]);
    });

    test('nested list', () {
      final doc = YamlEditor('''
- - 0
  - 1
- 2
''');
      doc.remove([0]);
      expect(doc.toString(), equals('''
- 2
'''));
      expectYamlBuilderValue(doc, [2]);
    });

    test('nested list (2)', () {
      final doc = YamlEditor('''
- - 0
  - 1
- 2
''');
      doc.remove([0, 1]);
      expect(doc.toString(), equals('''
- - 0
- 2
'''));
      expectYamlBuilderValue(doc, [
        [0],
        2
      ]);
    });

    test('nested map', () {
      final doc = YamlEditor('''
- - a: b
    c: d
''');
      doc.remove([0, 0, 'a']);
      expect(doc.toString(), equals('''
- - c: d
'''));
      expectYamlBuilderValue(doc, [
        [
          {'c': 'd'}
        ]
      ]);
    });
  });

  group('flow list', () {
    test('(1)', () {
      final doc = YamlEditor('[1, 2, 3]');
      doc.remove([1]);
      expect(doc.toString(), equals('[1, 3]'));
      expectYamlBuilderValue(doc, [1, 3]);
    });

    test('(2)', () {
      final doc = YamlEditor('[1, "b", "c"]');
      doc.remove([0]);
      expect(doc.toString(), equals('[ "b", "c"]'));
      expectYamlBuilderValue(doc, ['b', 'c']);
    });

    test('(3)', () {
      final doc = YamlEditor('[1, {a: 1}, "c"]');
      doc.remove([1]);
      expect(doc.toString(), equals('[1, "c"]'));
      expectYamlBuilderValue(doc, [1, 'c']);
    });

    test('(4) ', () {
      final doc = YamlEditor('["{}", b, "}{"]');
      doc.remove([1]);
      expect(doc.toString(), equals('["{}", "}{"]'));
    });

    test('(5) ', () {
      final doc = YamlEditor('["{}[],", [test, "{}[],", "{}[],"], "{}[],"]');
      doc.remove([1, 0]);
      expect(doc.toString(), equals('["{}[],", [ "{}[],", "{}[],"], "{}[],"]'));
    });
  });
}
