import 'package:pub/src/yaml_edit.dart';
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
  });
}
