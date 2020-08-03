// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('throws', () {
    test('RangeError in list if index is negative', () {
      final doc = YamlEditor("- YAML Ain't Markup Language");
      expect(() => doc.update([-1], 'test'), throwsRangeError);
    });

    test('RangeError in list if index is larger than list length', () {
      final doc = YamlEditor("- YAML Ain't Markup Language");
      expect(() => doc.update([2], 'test'), throwsRangeError);
    });

    test('PathError in list if attempting to set a key of a scalar', () {
      final doc = YamlEditor("- YAML Ain't Markup Language");
      expect(() => doc.update([0, 'a'], 'a'), throwsPathError);
    });
  });

  group('works on top-level', () {
    test('empty document', () {
      final doc = YamlEditor('');
      doc.update([], 'replacement');

      expect(doc.toString(), equals('replacement'));
      expectYamlBuilderValue(doc, 'replacement');
    });

    test('replaces string in document containing only a string', () {
      final doc = YamlEditor('test');
      doc.update([], 'replacement');

      expect(doc.toString(), equals('replacement'));
      expectYamlBuilderValue(doc, 'replacement');
    });

    test('replaces top-level string to map', () {
      final doc = YamlEditor('test');
      doc.update([], {'a': 1});

      expect(doc.toString(), equals('a: 1'));
      expectYamlBuilderValue(doc, {'a': 1});
    });

    test('replaces top-level list', () {
      final doc = YamlEditor('- 1');
      doc.update([], 'replacement');

      expect(doc.toString(), equals('replacement'));
      expectYamlBuilderValue(doc, 'replacement');
    });

    test('replaces top-level map', () {
      final doc = YamlEditor('a: 1');
      doc.update([], 'replacement');

      expect(doc.toString(), equals('replacement'));
      expectYamlBuilderValue(doc, 'replacement');
    });

    test('replaces top-level map with comment', () {
      final doc = YamlEditor('a: 1 # comment');
      doc.update([], 'replacement');

      expect(doc.toString(), equals('replacement # comment'));
      expectYamlBuilderValue(doc, 'replacement');
    });
  });

  group('replaces in', () {
    group('block map', () {
      test('(1)', () {
        final doc = YamlEditor("YAML: YAML Ain't Markup Language");
        doc.update(['YAML'], 'test');

        expect(doc.toString(), equals('YAML: test'));
        expectYamlBuilderValue(doc, {'YAML': 'test'});
      });

      test('(2)', () {
        final doc = YamlEditor('test: test');
        doc.update(['test'], []);

        expect(doc.toString(), equals('test: []'));
        expectYamlBuilderValue(doc, {'test': []});
      });

      test('with comment', () {
        final doc = YamlEditor("YAML: YAML Ain't Markup Language # comment");
        doc.update(['YAML'], 'test');

        expect(doc.toString(), equals('YAML: test # comment'));
        expectYamlBuilderValue(doc, {'YAML': 'test'});
      });

      test('nested', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5
c: 3
''');
        doc.update(['b', 'e'], 6);

        expect(doc.toString(), equals('''
a: 1
b: 
  d: 4
  e: 6
c: 3
'''));

        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': {'d': 4, 'e': 6},
          'c': 3
        });
      });

      test('nested (2)', () {
        final doc = YamlEditor('''
a: 1
b: {d: 4, e: 5}
c: 3
''');
        doc.update(['b', 'e'], 6);

        expect(doc.toString(), equals('''
a: 1
b: {d: 4, e: 6}
c: 3
'''));
        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': {'d': 4, 'e': 6},
          'c': 3
        });
      });

      test('nested (3)', () {
        final doc = YamlEditor('''
a:
 b: 4
''');
        doc.update(['a'], true);

        expect(doc.toString(), equals('''
a: true
'''));

        expectYamlBuilderValue(doc, {'a': true});
      });

      test('nested (4)', () {
        final doc = YamlEditor('''
a: 1
''');
        doc.update([
          'a'
        ], [
          {'a': true, 'b': false}
        ]);

        expectYamlBuilderValue(doc, {
          'a': [
            {'a': true, 'b': false}
          ]
        });
      });

      test('nested (5)', () {
        final doc = YamlEditor('''
a: 
  - a: 1
    b: 2
  - null
''');
        doc.update(['a', 0], false);
        expect(doc.toString(), equals('''
a: 
  - false

  - null
'''));
        expectYamlBuilderValue(doc, {
          'a': [false, null]
        });
      });

      test('nested (6)', () {
        final doc = YamlEditor('''
a: 
  - - 1
    - 2
  - null
''');
        doc.update(['a', 0], false);
        expect(doc.toString(), equals('''
a: 
  - false

  - null
'''));
        expectYamlBuilderValue(doc, {
          'a': [false, null]
        });
      });

      test('nested (7)', () {
        final doc = YamlEditor('''
a:
  - - 0
b: false
''');
        doc.update(['a', 0], true);

        expect(doc.toString(), equals('''
a:
  - true

b: false
'''));
      });

      test('nested scalar -> flow list', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5
c: 3
''');
        doc.update(['b', 'e'], [1, 2, 3]);

        expect(doc.toString(), equals('''
a: 1
b: 
  d: 4
  e: 
    - 1
    - 2
    - 3
c: 3
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

      test('nested block map -> scalar', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5
c: 3
''');
        doc.update(['b'], 2);

        expect(doc.toString(), equals('''
a: 1
b: 2
c: 3
'''));
        expectYamlBuilderValue(doc, {'a': 1, 'b': 2, 'c': 3});
      });

      test('nested block map -> scalar with comments', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5


# comment
''');
        doc.update(['b'], 2);

        expect(doc.toString(), equals('''
a: 1
b: 2


# comment
'''));
        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': 2,
        });
      });

      test('nested scalar -> block map', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5
c: 3
''');
        doc.update(['b', 'e'], {'x': 3, 'y': 4});

        expect(doc.toString(), equals('''
a: 1
b: 
  d: 4
  e: 
    x: 3
    y: 4
c: 3
'''));
        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': {
            'd': 4,
            'e': {'x': 3, 'y': 4}
          },
          'c': 3
        });
      });

      test('nested block map with comments', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: 5 # comment
c: 3
''');
        doc.update(['b', 'e'], 6);

        expect(doc.toString(), equals('''
a: 1
b: 
  d: 4
  e: 6 # comment
c: 3
'''));
        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': {'d': 4, 'e': 6},
          'c': 3
        });
      });

      test('nested block map with comments (2)', () {
        final doc = YamlEditor('''
a: 1
b: 
  d: 4 # comment
# comment
  e: 5 # comment
# comment
c: 3
''');
        doc.update(['b', 'e'], 6);

        expect(doc.toString(), equals('''
a: 1
b: 
  d: 4 # comment
# comment
  e: 6 # comment
# comment
c: 3
'''));
        expectYamlBuilderValue(doc, {
          'a': 1,
          'b': {'d': 4, 'e': 6},
          'c': 3
        });
      });
    });

    group('flow map', () {
      test('(1)', () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(['YAML'], 'test');

        expect(doc.toString(), equals('{YAML: test}'));
        expectYamlBuilderValue(doc, {'YAML': 'test'});
      });

      test('(2)', () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(['YAML'], 'd9]zH`FoYC/>]');

        expect(doc.toString(), equals('{YAML: "d9]zH`FoYC\\/>]"}'));
        expectYamlBuilderValue(doc, {'YAML': 'd9]zH`FoYC/>]'});
      });

      test('with spacing', () {
        final doc = YamlEditor(
            "{ YAML:  YAML Ain't Markup Language , XML: Extensible Markup Language , HTML: Hypertext Markup Language }");
        doc.update(['XML'], 'XML Markup Language');

        expect(
            doc.toString(),
            equals(
                "{ YAML:  YAML Ain't Markup Language , XML: XML Markup Language, HTML: Hypertext Markup Language }"));
        expectYamlBuilderValue(doc, {
          'YAML': "YAML Ain't Markup Language",
          'XML': 'XML Markup Language',
          'HTML': 'Hypertext Markup Language'
        });
      });
    });

    group('block list', () {
      test('(1)', () {
        final doc = YamlEditor("- YAML Ain't Markup Language");
        doc.update([0], 'test');

        expect(doc.toString(), equals('- test'));
        expectYamlBuilderValue(doc, ['test']);
      });

      test('nested (1)', () {
        final doc = YamlEditor("- YAML Ain't Markup Language");
        doc.update([0], [1, 2]);

        expect(doc.toString(), equals('- - 1\n  - 2'));
        expectYamlBuilderValue(doc, [
          [1, 2]
        ]);
      });

      test('with comment', () {
        final doc = YamlEditor("- YAML Ain't Markup Language # comment");
        doc.update([0], 'test');

        expect(doc.toString(), equals('- test # comment'));
        expectYamlBuilderValue(doc, ['test']);
      });

      test('with comment and spaces', () {
        final doc = YamlEditor("-  YAML Ain't Markup Language  # comment");
        doc.update([0], 'test');

        expect(doc.toString(), equals('-  test  # comment'));
        expectYamlBuilderValue(doc, ['test']);
      });

      test('nested (2)', () {
        final doc = YamlEditor('''
- 0
- - 0
  - 1
  - 2
- 2
- 3
''');
        doc.update([1, 1], 4);
        expect(doc.toString(), equals('''
- 0
- - 0
  - 4
  - 2
- 2
- 3
'''));

        expectYamlBuilderValue(doc, [
          0,
          [0, 4, 2],
          2,
          3
        ]);
      });

      test('nested (3)', () {
        final doc = YamlEditor('''
- 0
- 1
''');
        doc.update([0], {'item': 'Super Hoop', 'quantity': 1});
        doc.update([1], {'item': 'BasketBall', 'quantity': 4});
        expect(doc.toString(), equals('''
- item: Super Hoop
  quantity: 1
- item: BasketBall
  quantity: 4
'''));

        expectYamlBuilderValue(doc, [
          {'item': 'Super Hoop', 'quantity': 1},
          {'item': 'BasketBall', 'quantity': 4}
        ]);
      });

      test('nested list flow map -> scalar', () {
        final doc = YamlEditor('''
- 0
- {a: 1, b: 2}
- 2
- 3
''');
        doc.update([1], 4);
        expect(doc.toString(), equals('''
- 0
- 4
- 2
- 3
'''));
        expectYamlBuilderValue(doc, [0, 4, 2, 3]);
      });

      test('nested list-map-list-number update', () {
        final doc = YamlEditor('''
- 0
- a:
   - 1
   - 2
   - 3
- 2
- 3
''');
        doc.update([1, 'a', 0], 15);
        expect(doc.toString(), equals('''
- 0
- a:
   - 15
   - 2
   - 3
- 2
- 3
'''));
        expectYamlBuilderValue(doc, [
          0,
          {
            'a': [15, 2, 3]
          },
          2,
          3
        ]);
      });
    });

    group('flow list', () {
      test('(1)', () {
        final doc = YamlEditor("[YAML Ain't Markup Language]");
        doc.update([0], 'test');

        expect(doc.toString(), equals('[test]'));
        expectYamlBuilderValue(doc, ['test']);
      });

      test('(2)', () {
        final doc = YamlEditor("[YAML Ain't Markup Language]");
        doc.update([0], [1, 2, 3]);

        expect(doc.toString(), equals('[[1, 2, 3]]'));
        expectYamlBuilderValue(doc, [
          [1, 2, 3]
        ]);
      });

      test('with spacing (1)', () {
        final doc = YamlEditor('[ 0 , 1 , 2 , 3 ]');
        doc.update([1], 4);

        expect(doc.toString(), equals('[ 0 , 4, 2 , 3 ]'));
        expectYamlBuilderValue(doc, [0, 4, 2, 3]);
      });
    });
  });

  group('adds to', () {
    group('flow map', () {
      test('that is empty ', () {
        final doc = YamlEditor('{}');
        doc.update(['a'], 1);
        expect(doc.toString(), equals('{a: 1}'));
        expectYamlBuilderValue(doc, {'a': 1});
      });

      test('(1)', () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(['XML'], 'Extensible Markup Language');

        expect(
            doc.toString(),
            equals(
                "{XML: Extensible Markup Language, YAML: YAML Ain't Markup Language}"));
        expectYamlBuilderValue(doc, {
          'XML': 'Extensible Markup Language',
          'YAML': "YAML Ain't Markup Language",
        });
      });
    });

    group('block map', () {
      test('(1)', () {
        final doc = YamlEditor('''
a: 1
b: 2
c: 3
''');
        doc.update(['d'], 4);
        expect(doc.toString(), equals('''
a: 1
b: 2
c: 3
d: 4
'''));
        expectYamlBuilderValue(doc, {'a': 1, 'b': 2, 'c': 3, 'd': 4});
      });

      /// Regression testing to ensure it works without leading wtesttespace
      test('(2)', () {
        final doc = YamlEditor('a: 1');
        doc.update(['b'], 2);
        expect(doc.toString(), equals('''a: 1
b: 2
'''));
        expectYamlBuilderValue(doc, {'a': 1, 'b': 2});
      });

      test('(3)', () {
        final doc = YamlEditor('''
a:
  aa: 1
  zz: 1
''');
        doc.update([
          'a',
          'bb'
        ], {
          'aaa': {'dddd': 'c'},
          'bbb': [0, 1, 2]
        });

        expect(doc.toString(), equals('''
a:
  aa: 1
  bb: 
    aaa:
      dddd: c
    bbb:
      - 0
      - 1
      - 2
  zz: 1
'''));
        expectYamlBuilderValue(doc, {
          'a': {
            'aa': 1,
            'bb': {
              'aaa': {'dddd': 'c'},
              'bbb': [0, 1, 2]
            },
            'zz': 1
          }
        });
      });

      test('(4)', () {
        final doc = YamlEditor('''
a:
  aa: 1
  zz: 1
''');
        doc.update([
          'a',
          'bb'
        ], [
          0,
          [1, 2],
          {'aaa': 'b', 'bbb': 'c'}
        ]);

        expect(doc.toString(), equals('''
a:
  aa: 1
  bb: 
    - 0
    - - 1
      - 2
    - aaa: b
      bbb: c
  zz: 1
'''));
        expectYamlBuilderValue(doc, {
          'a': {
            'aa': 1,
            'bb': [
              0,
              [1, 2],
              {'aaa': 'b', 'bbb': 'c'}
            ],
            'zz': 1
          }
        });
      });

      test('with complex keys', () {
        final doc = YamlEditor('''
? Sammy Sosa
? Ken Griff''');
        doc.update(['Mark McGwire'], null);
        expect(doc.toString(), equals('''
? Sammy Sosa
? Ken Griff
Mark McGwire: null
'''));
        expectYamlBuilderValue(
            doc, {'Sammy Sosa': null, 'Ken Griff': null, 'Mark McGwire': null});
      });

      test('with trailing newline', () {
        final doc = YamlEditor('''
a: 1
b: 2
c: 3


''');
        doc.update(['d'], 4);
        expect(doc.toString(), equals('''
a: 1
b: 2
c: 3
d: 4


'''));
        expectYamlBuilderValue(doc, {'a': 1, 'b': 2, 'c': 3, 'd': 4});
      });
    });
  });
}
