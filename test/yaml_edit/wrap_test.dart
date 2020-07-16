// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:pub/src/yaml_edit/src/equality.dart';
import 'package:pub/src/yaml_edit/src/wrap.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

void main() {
  group('wrapAsYamlNode', () {
    group('checks for invalid scalars', () {
      test('fails to wrap an invalid scalar', () {
        expect(() => wrapAsYamlNode(File('test.dart')), throwsArgumentError);
      });

      test('fails to wrap an invalid map', () {
        expect(() => wrapAsYamlNode({'a': File('test.dart')}),
            throwsArgumentError);
      });

      test('fails to wrap an invalid list', () {
        expect(
            () => wrapAsYamlNode([
                  'a',
                  [File('test.dart')]
                ]),
            throwsArgumentError);
      });

      test('checks YamlScalar for invalid scalar value', () {
        expect(() => wrapAsYamlNode(YamlScalar.wrap(File('test.dart'))),
            throwsArgumentError);
      });

      test('checks YamlMap for deep invalid scalar value', () {
        expect(
            () => wrapAsYamlNode(YamlMap.wrap({
                  'a': {'b': File('test.dart')}
                })),
            throwsArgumentError);
      });

      test('checks YamlList for deep invalid scalar value', () {
        expect(
            () => wrapAsYamlNode(YamlList.wrap([
                  'a',
                  [File('test.dart')]
                ])),
            throwsArgumentError);
      });
    });

    test('wraps scalars', () {
      final scalar = wrapAsYamlNode('foo');

      expect((scalar as YamlScalar).style, equals(ScalarStyle.ANY));
      expect(scalar.value, equals('foo'));
    });

    test('wraps scalars with style', () {
      final scalar =
          wrapAsYamlNode('foo', scalarStyle: ScalarStyle.DOUBLE_QUOTED);

      expect((scalar as YamlScalar).style, equals(ScalarStyle.DOUBLE_QUOTED));
      expect(scalar.value, equals('foo'));
    });

    test('wraps lists', () {
      final list = wrapAsYamlNode([
        [1, 2, 3],
        {
          'foo': 'bar',
          'nested': [4, 5, 6]
        },
        'value'
      ]);

      expect(
          list,
          equals([
            [1, 2, 3],
            {
              'foo': 'bar',
              'nested': [4, 5, 6]
            },
            'value'
          ]));
      expect((list as YamlList).style, equals(CollectionStyle.ANY));
      expect((list as YamlList)[0].style, equals(CollectionStyle.ANY));
      expect((list as YamlList)[1].style, equals(CollectionStyle.ANY));
    });

    test('wraps lists with collectionStyle', () {
      final list = wrapAsYamlNode([
        [1, 2, 3],
        {
          'foo': 'bar',
          'nested': [4, 5, 6]
        },
        'value'
      ], collectionStyle: CollectionStyle.BLOCK);

      expect((list as YamlList).style, equals(CollectionStyle.BLOCK));
      expect((list as YamlList)[0].style, equals(CollectionStyle.ANY));
      expect((list as YamlList)[1].style, equals(CollectionStyle.ANY));
    });

    test('wraps nested lists while preserving style', () {
      final list = wrapAsYamlNode([
        wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.FLOW),
        wrapAsYamlNode({
          'foo': 'bar',
          'nested': [4, 5, 6]
        }, collectionStyle: CollectionStyle.FLOW),
        'value'
      ], collectionStyle: CollectionStyle.BLOCK);

      expect((list as YamlList).style, equals(CollectionStyle.BLOCK));
      expect((list as YamlList)[0].style, equals(CollectionStyle.FLOW));
      expect((list as YamlList)[1].style, equals(CollectionStyle.FLOW));
    });

    test('wraps maps', () {
      final map = wrapAsYamlNode({
        'list': [1, 2, 3],
        'map': {
          'foo': 'bar',
          'nested': [4, 5, 6]
        },
        'scalar': 'value'
      });

      expect(
          map,
          equals({
            'list': [1, 2, 3],
            'map': {
              'foo': 'bar',
              'nested': [4, 5, 6]
            },
            'scalar': 'value'
          }));

      expect((map as YamlMap).style, equals(CollectionStyle.ANY));
    });

    test('wraps maps with collectionStyle', () {
      final map = wrapAsYamlNode({
        'list': [1, 2, 3],
        'map': {
          'foo': 'bar',
          'nested': [4, 5, 6]
        },
        'scalar': 'value'
      }, collectionStyle: CollectionStyle.BLOCK);

      expect((map as YamlMap).style, equals(CollectionStyle.BLOCK));
    });

    test('wraps nested maps while preserving style', () {
      final map = wrapAsYamlNode({
        'list':
            wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.FLOW),
        'map': wrapAsYamlNode({
          'foo': 'bar',
          'nested': [4, 5, 6]
        }, collectionStyle: CollectionStyle.BLOCK),
        'scalar': 'value'
      }, collectionStyle: CollectionStyle.BLOCK);

      expect((map as YamlMap).style, equals(CollectionStyle.BLOCK));
      expect((map as YamlMap)['list'].style, equals(CollectionStyle.FLOW));
      expect((map as YamlMap)['map'].style, equals(CollectionStyle.BLOCK));
    });

    test('works with YamlMap.wrap', () {
      final map = wrapAsYamlNode({
        'list':
            wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.FLOW),
        'map': YamlMap.wrap({
          'foo': 'bar',
          'nested': [4, 5, 6]
        }),
      }, collectionStyle: CollectionStyle.BLOCK);

      expect((map as YamlMap).style, equals(CollectionStyle.BLOCK));
      expect((map as YamlMap)['list'].style, equals(CollectionStyle.FLOW));
      expect((map as YamlMap)['map'].style, equals(CollectionStyle.ANY));
    });
  });

  group('deepHashCode', () {
    test('returns the same result for scalar and its value', () {
      final hashCode1 = deepHashCode('foo');
      final hashCode2 = deepHashCode(wrapAsYamlNode('foo'));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns different results for different values', () {
      final hashCode1 = deepHashCode('foo');
      final hashCode2 = deepHashCode(wrapAsYamlNode('bar'));

      expect(hashCode1, notEquals(hashCode2));
    });

    test('returns the same result for YamlScalar with style and its value', () {
      final hashCode1 = deepHashCode('foo');
      final hashCode2 =
          deepHashCode(wrapAsYamlNode('foo', scalarStyle: ScalarStyle.LITERAL));

      expect(hashCode1, equals(hashCode2));
    });

    test(
        'returns the same result for two YamlScalars with same value but different styles',
        () {
      final hashCode1 =
          deepHashCode(wrapAsYamlNode('foo', scalarStyle: ScalarStyle.PLAIN));
      final hashCode2 =
          deepHashCode(wrapAsYamlNode('foo', scalarStyle: ScalarStyle.LITERAL));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the same result for list and its value', () {
      final hashCode1 = deepHashCode([1, 2, 3]);
      final hashCode2 = deepHashCode(wrapAsYamlNode([1, 2, 3]));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the same result for list and the YamlList.wrap() value', () {
      final hashCode1 = deepHashCode([
        1,
        [1, 2],
        3
      ]);
      final hashCode2 = deepHashCode(YamlList.wrap([
        1,
        YamlList.wrap([1, 2]),
        3
      ]));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the different results for different lists', () {
      final hashCode1 = deepHashCode([1, 2, 3]);
      final hashCode2 = deepHashCode([1, 2, 4]);
      final hashCode3 = deepHashCode([1, 2, 3, 4]);

      expect(hashCode1, notEquals(hashCode2));
      expect(hashCode2, notEquals(hashCode3));
      expect(hashCode3, notEquals(hashCode1));
    });

    test('returns the same result for YamlList with style and its value', () {
      final hashCode1 = deepHashCode([1, 2, 3]);
      final hashCode2 = deepHashCode(
          wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.FLOW));

      expect(hashCode1, equals(hashCode2));
    });

    test(
        'returns the same result for two YamlLists with same value but different styles',
        () {
      final hashCode1 = deepHashCode(
          wrapAsYamlNode([1, 2, 3], collectionStyle: CollectionStyle.BLOCK));
      final hashCode2 = deepHashCode(wrapAsYamlNode([1, 2, 3]));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the same result for a map and its value', () {
      final hashCode1 = deepHashCode({'a': 1, 'b': 2});
      final hashCode2 = deepHashCode(wrapAsYamlNode({'a': 1, 'b': 2}));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the same result for list and the YamlList.wrap() value', () {
      final hashCode1 = deepHashCode({
        'a': 1,
        'b': 2,
        'c': {'d': 4, 'e': 5}
      });
      final hashCode2 = deepHashCode(YamlMap.wrap({
        'a': 1,
        'b': 2,
        'c': YamlMap.wrap({'d': 4, 'e': 5})
      }));

      expect(hashCode1, equals(hashCode2));
    });

    test('returns the different results for different maps', () {
      final hashCode1 = deepHashCode({'a': 1, 'b': 2});
      final hashCode2 = deepHashCode({'a': 1, 'b': 3});
      final hashCode3 = deepHashCode({'a': 1, 'b': 2, 'c': 3});

      expect(hashCode1, notEquals(hashCode2));
      expect(hashCode2, notEquals(hashCode3));
      expect(hashCode3, notEquals(hashCode1));
    });

    test('returns the same result for YamlMap with style and its value', () {
      final hashCode1 = deepHashCode({'a': 1, 'b': 2});
      final hashCode2 = deepHashCode(wrapAsYamlNode({'a': 1, 'b': 2},
          collectionStyle: CollectionStyle.FLOW));

      expect(hashCode1, equals(hashCode2));
    });

    test(
        'returns the same result for two YamlMaps with same value but different styles',
        () {
      final hashCode1 = deepHashCode(wrapAsYamlNode({'a': 1, 'b': 2},
          collectionStyle: CollectionStyle.BLOCK));
      final hashCode2 = deepHashCode(wrapAsYamlNode({'a': 1, 'b': 2},
          collectionStyle: CollectionStyle.FLOW));

      expect(hashCode1, equals(hashCode2));
    });
  });
}
