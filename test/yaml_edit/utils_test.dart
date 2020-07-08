// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/yaml_edit.dart';
import 'package:pub/src/yaml_edit/utils.dart';
import 'package:pub/src/yaml_edit/wrap.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  group('styling options', () {
    group('update', () {
      test('flow map with style', () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(['YAML'],
            wrapAsYamlNode('hi', scalarStyle: ScalarStyle.DOUBLE_QUOTED));

        expect(doc.toString(), equals('{YAML: "hi"}'));
        expectYamlBuilderValue(doc, {'YAML': 'hi'});
      });

      test('prevents block scalars in flow map', () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(
            ['YAML'], wrapAsYamlNode('test', scalarStyle: ScalarStyle.FOLDED));

        expect(doc.toString(), equals('{YAML: test}'));
        expectYamlBuilderValue(doc, {'YAML': 'test'});
      });

      test('wraps string in double-quotes if it contains dangerous characters',
          () {
        final doc = YamlEditor("{YAML: YAML Ain't Markup Language}");
        doc.update(
            ['YAML'], wrapAsYamlNode('> test', scalarStyle: ScalarStyle.PLAIN));

        expect(doc.toString(), equals('{YAML: "> test"}'));
        expectYamlBuilderValue(doc, {'YAML': '> test'});
      });

      test('list in map', () {
        final doc = YamlEditor('''YAML: YAML Ain't Markup Language''');
        doc.update(['YAML'],
            wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.FLOW));

        expect(doc.toString(), equals('YAML: [1, 2, 3]'));
        expectYamlBuilderValue(doc, {
          'YAML': [1, 2, 3]
        });
      });

      test('nested map', () {
        final doc = YamlEditor('''YAML: YAML Ain't Markup Language''');
        doc.update(
            ['YAML'],
            wrapAsYamlNode({'YAML': "YAML Ain't Markup Language"},
                collectionStyle: CollectionStyle.FLOW));

        expect(
            doc.toString(), equals("YAML: {YAML: YAML Ain't Markup Language}"));
        expectYamlBuilderValue(doc, {
          'YAML': {'YAML': "YAML Ain't Markup Language"}
        });
      });

      test('nested list', () {
        final doc = YamlEditor('- 0');
        doc.update(
            [0],
            wrapAsYamlNode([
              1,
              2,
              wrapAsYamlNode([3, 4], collectionStyle: CollectionStyle.FLOW),
              5
            ]));

        expect(doc.toString(), equals('''
- - 1
  - 2
  - [3, 4]
  - 5'''));
        expectYamlBuilderValue(doc, [
          [
            1,
            2,
            [3, 4],
            5
          ]
        ]);
      });

      test('different scalars in block list!', () {
        final doc = YamlEditor('- 0');
        doc.update(
            [0],
            wrapAsYamlNode([
              wrapAsYamlNode('plain string', scalarStyle: ScalarStyle.PLAIN),
              wrapAsYamlNode('folded string', scalarStyle: ScalarStyle.FOLDED),
              wrapAsYamlNode('single-quoted string',
                  scalarStyle: ScalarStyle.SINGLE_QUOTED),
              wrapAsYamlNode('literal string',
                  scalarStyle: ScalarStyle.LITERAL),
              wrapAsYamlNode('double-quoted string',
                  scalarStyle: ScalarStyle.DOUBLE_QUOTED),
            ]));

        expect(doc.toString(), equals('''
- - plain string
  - >-
      folded string
  - 'single-quoted string'
  - |-
      literal string
  - "double-quoted string"'''));
        expectYamlBuilderValue(doc, [
          [
            'plain string',
            'folded string',
            'single-quoted string',
            'literal string',
            'double-quoted string',
          ]
        ]);
      });

      test('different scalars in block map!', () {
        final doc = YamlEditor('strings: strings');
        doc.update(
            ['strings'],
            wrapAsYamlNode({
              'plain': wrapAsYamlNode('string', scalarStyle: ScalarStyle.PLAIN),
              'folded':
                  wrapAsYamlNode('string', scalarStyle: ScalarStyle.FOLDED),
              'single-quoted': wrapAsYamlNode('string',
                  scalarStyle: ScalarStyle.SINGLE_QUOTED),
              'literal':
                  wrapAsYamlNode('string', scalarStyle: ScalarStyle.LITERAL),
              'double-quoted': wrapAsYamlNode('string',
                  scalarStyle: ScalarStyle.DOUBLE_QUOTED),
            }));

        expect(doc.toString(), equals('''
strings: 
  plain: string
  folded: >-
      string
  single-quoted: 'string'
  literal: |-
      string
  double-quoted: "string"'''));
        expectYamlBuilderValue(doc, {
          'strings': {
            'plain': 'string',
            'folded': 'string',
            'single-quoted': 'string',
            'literal': 'string',
            'double-quoted': 'string',
          }
        });
      });

      test('different scalars in flow list!', () {
        final doc = YamlEditor('[0]');
        doc.update(
            [0],
            wrapAsYamlNode([
              wrapAsYamlNode('plain string', scalarStyle: ScalarStyle.PLAIN),
              wrapAsYamlNode('folded string', scalarStyle: ScalarStyle.FOLDED),
              wrapAsYamlNode('single-quoted string',
                  scalarStyle: ScalarStyle.SINGLE_QUOTED),
              wrapAsYamlNode('literal string',
                  scalarStyle: ScalarStyle.LITERAL),
              wrapAsYamlNode('double-quoted string',
                  scalarStyle: ScalarStyle.DOUBLE_QUOTED),
            ]));

        expect(
            doc.toString(),
            equals(
                '[[plain string, folded string, \'single-quoted string\', literal string, "double-quoted string"]]'));
        expectYamlBuilderValue(doc, [
          [
            'plain string',
            'folded string',
            'single-quoted string',
            'literal string',
            'double-quoted string',
          ]
        ]);
      });

      test('wraps non-printable strings in double-quotes in flow context', () {
        final doc = YamlEditor('[0]');
        doc.update([0], '\x00\x07\x08\x0b\x0c\x0d\x1b\x85\xa0\u2028\u2029"');
        expect(
            doc.toString(), equals('["\\0\\a\\b\\v\\f\\r\\e\\N\\_\\L\\P\\""]'));
        expectYamlBuilderValue(
            doc, ['\x00\x07\x08\x0b\x0c\x0d\x1b\x85\xa0\u2028\u2029"']);
      });

      test('wraps non-printable strings in double-quotes in block context', () {
        final doc = YamlEditor('- 0');
        doc.update([0], '\x00\x07\x08\x0b\x0c\x0d\x1b\x85\xa0\u2028\u2029"');
        expect(
            doc.toString(), equals('- "\\0\\a\\b\\v\\f\\r\\e\\N\\_\\L\\P\\""'));
        expectYamlBuilderValue(
            doc, ['\x00\x07\x08\x0b\x0c\x0d\x1b\x85\xa0\u2028\u2029"']);
      });

      test('generates folded strings properly', () {
        final doc = YamlEditor('');
        doc.update(
            [], wrapAsYamlNode('test\ntest', scalarStyle: ScalarStyle.FOLDED));
        expect(doc.toString(), equals('>-\n  test\n\n  test'));
      });

      test('rewrites folded strings properly', () {
        final doc = YamlEditor('''
- >
    folded string
''');
        doc.update(
            [0], wrapAsYamlNode('test\ntest', scalarStyle: ScalarStyle.FOLDED));
        expect(doc.toString(), equals('''
- >-
    test

    test
'''));
      });

      test('rewrites folded strings properly (1)', () {
        final doc = YamlEditor('''
- >
    folded string''');
        doc.update(
            [0], wrapAsYamlNode('test\ntest', scalarStyle: ScalarStyle.FOLDED));
        expect(doc.toString(), equals('''
- >-
    test

    test'''));
      });

      test('generates literal strings properly', () {
        final doc = YamlEditor('');
        doc.update(
            [], wrapAsYamlNode('test\ntest', scalarStyle: ScalarStyle.LITERAL));
        expect(doc.toString(), equals('|-\n  test\n  test'));
      });

      test('rewrites literal strings properly', () {
        final doc = YamlEditor('''
- |
    literal string
''');
        doc.update([0],
            wrapAsYamlNode('test\ntest', scalarStyle: ScalarStyle.LITERAL));
        expect(doc.toString(), equals('''
- |-
    test
    test
'''));
      });

      test('prevents literal strings in flow maps, even if nested', () {
        final doc = YamlEditor('''
{1: 1}
''');
        doc.update([
          1
        ], [
          wrapAsYamlNode('d9]zH`FoYC/>]', scalarStyle: ScalarStyle.LITERAL)
        ]);

        expect(doc.toString(), equals('''
{1: ["d9]zH`FoYC\\/>]"]}
'''));
        expect((doc.parseAt([1, 0]) as dynamic).style,
            equals(ScalarStyle.DOUBLE_QUOTED));
      });

      test('prevents literal empty strings', () {
        final doc = YamlEditor('''
a:
  c: 1
''');
        doc.update([
          'a'
        ], {
          'f': wrapAsYamlNode('', scalarStyle: ScalarStyle.LITERAL),
          'g': 1
        });

        expect(doc.toString(), equals('''
a: 
  f: ""
  g: 1
'''));
      });

      test('prevents literal strings with leading spaces', () {
        final doc = YamlEditor('''
a:
  c: 1
''');
        doc.update([
          'a'
        ], {
          'f': wrapAsYamlNode(' a', scalarStyle: ScalarStyle.LITERAL),
          'g': 1
        });

        expect(doc.toString(), equals('''
a: 
  f: " a"
  g: 1
'''));
      });

      test(
          'flow collection structure does not get substringed when added to block structure',
          () {
        final doc = YamlEditor('''
a:
  - false
''');
        doc.prependToList(['a'],
            wrapAsYamlNode([1234], collectionStyle: CollectionStyle.FLOW));
        expect(doc.toString(), equals('''
a:
  - [1234]
  - false
'''));
        expectYamlBuilderValue(doc, {
          'a': [
            [1234],
            false
          ]
        });
      });
    });
  });

  group('assertValidScalar', () {
    test('does nothing with a boolean', () {
      expect(() => assertValidScalar(true), returnsNormally);
    });

    test('does nothing with a number', () {
      expect(() => assertValidScalar(1.12), returnsNormally);
    });
    test('does nothing with infinity', () {
      expect(() => assertValidScalar(double.infinity), returnsNormally);
    });
    test('does nothing with a String', () {
      expect(() => assertValidScalar('test'), returnsNormally);
    });

    test('does nothing with null', () {
      expect(() => assertValidScalar(null), returnsNormally);
    });

    test('throws on map', () {
      expect(() => assertValidScalar({'a': 1}), throwsArgumentError);
    });

    test('throws on list', () {
      expect(() => assertValidScalar([1]), throwsArgumentError);
    });
  });
}
