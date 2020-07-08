// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  group('throws', () {
    test('PathError if key does not exist', () {
      final doc = YamlEditor('{a: 4}');
      final path = ['b'];

      expect(() => doc.parseAt(path), throwsPathError);
    });

    test('PathError if path tries to go deeper into a scalar', () {
      final doc = YamlEditor('{a: 4}');
      final path = ['a', 'b'];

      expect(() => doc.parseAt(path), throwsPathError);
    });

    test('PathError if index is out of bounds', () {
      final doc = YamlEditor('[0,1]');
      final path = [2];

      expect(() => doc.parseAt(path), throwsPathError);
    });

    test('PathError if index is not an integer', () {
      final doc = YamlEditor('[0,1]');
      final path = ['2'];

      expect(() => doc.parseAt(path), throwsPathError);
    });
  });

  group('orElse provides a default value', () {
    test('simple example with null return ', () {
      final doc = YamlEditor('{a: {d: 4}, c: ~}');
      var result = doc.parseAt(['b'], orElse: () => null);

      expect(result, equals(null));
    });

    test('simple example with map return', () {
      final doc = YamlEditor('{a: {d: 4}, c: ~}');
      var result = doc.parseAt(['b'], orElse: () => wrapAsYamlNode({'a': 42}));

      expect(result, isA<YamlMap>());
      expect(result.value, equals({'a': 42}));
    });

    test('simple example with scalar return', () {
      final doc = YamlEditor('{a: {d: 4}, c: ~}');
      var result = doc.parseAt(['b'], orElse: () => wrapAsYamlNode(42));

      expect(result, isA<YamlScalar>());
      expect(result.value, equals(42));
    });

    test('simple example with list return', () {
      final doc = YamlEditor('{a: {d: 4}, c: ~}');
      var result = doc.parseAt(['b'], orElse: () => wrapAsYamlNode([42]));

      expect(result, isA<YamlList>());
      expect(result.value, equals([42]));
    });
  });

  group('returns a YamlNode', () {
    test('with the correct type', () {
      final doc = YamlEditor("YAML: YAML Ain't Markup Language");
      final expectedYamlScalar = doc.parseAt(['YAML']);

      expect(expectedYamlScalar, isA<YamlScalar>());
    });

    test('with the correct value', () {
      final doc = YamlEditor("YAML: YAML Ain't Markup Language");

      expect(doc.parseAt(['YAML']).value, "YAML Ain't Markup Language");
    });

    test('with the correct value in nested collection', () {
      final doc = YamlEditor('''
a: 1
b: 
  d: 4
  e: [5, 6, 7]
c: 3
''');

      expect(doc.parseAt(['b', 'e', 2]).value, 7);
    });

    test('with the correct type (2)', () {
      final doc = YamlEditor("YAML: YAML Ain't Markup Language");
      final expectedYamlMap = doc.parseAt([]);

      expect(expectedYamlMap is YamlMap, equals(true));
    });

    test('that is immutable', () {
      final doc = YamlEditor("YAML: YAML Ain't Markup Language");
      final expectedYamlMap = doc.parseAt([]);

      expect(() => (expectedYamlMap as YamlMap)['YAML'] = 'test',
          throwsUnsupportedError);
    });

    test('that has immutable children', () {
      final doc = YamlEditor("YAML: ['Y', 'A', 'M', 'L']");
      final expectedYamlMap = doc.parseAt([]);

      expect(() => (expectedYamlMap as YamlMap)['YAML'][0] = 'X',
          throwsUnsupportedError);
    });
  });

  test('works with map keys', () {
    final doc = YamlEditor('{a: {{[1, 2]: 3}: 4}}');
    expect(
        doc.parseAt([
          'a',
          {
            [1, 2]: 3
          }
        ]).value,
        equals(4));
  });
}
