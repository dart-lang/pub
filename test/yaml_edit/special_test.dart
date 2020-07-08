// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('test if "No" is recognized as false', () {
    final doc = YamlEditor('''
~: null
false: false
No: No
true: true
''');
    doc.update([null], 'tilde');
    doc.update([false], false);
    doc.update(['No'], 'no');
    doc.update([true], 'true');

    expect(doc.toString(), equals('''
~: tilde
false: false
No: no
true: "true"
'''));

    expectYamlBuilderValue(
        doc, {null: 'tilde', false: false, 'No': 'no', true: 'true'});
  });

  test('array keys are recognized', () {
    final doc = YamlEditor('{[1,2,3]: a}');
    doc.update([
      [1, 2, 3]
    ], 'sums to 6');

    expect(doc.toString(), equals('{[1,2,3]: sums to 6}'));
    expectYamlBuilderValue(doc, {
      [1, 2, 3]: 'sums to 6'
    });
  });

  test('map keys are recognized', () {
    final doc = YamlEditor('{{a: 1}: a}');
    doc.update([
      {'a': 1}
    ], 'sums to 6');

    expect(doc.toString(), equals('{{a: 1}: sums to 6}'));
    expectYamlBuilderValue(doc, {
      {'a': 1}: 'sums to 6'
    });
  });

  test('documents can have directives', () {
    final doc = YamlEditor('''%YAML 1.2
--- text''');
    doc.update([], 'test');

    expect(doc.toString(), equals('%YAML 1.2\n--- test'));
    expectYamlBuilderValue(doc, 'test');
  });

  test('tags should be removed if value is changed', () {
    final doc = YamlEditor('''
 - !!str a
 - b
 - !!int 42
 - d
''');
    doc.update([2], 'test');

    expect(doc.toString(), equals('''
 - !!str a
 - b
 - test
 - d
'''));
    expectYamlBuilderValue(doc, ['a', 'b', 'test', 'd']);
  });

  test('tags should be removed if key is changed', () {
    final doc = YamlEditor('''
!!str a: b
c: !!int 42
e: !!str f
g: h
!!str 23: !!bool false
''');
    doc.remove(['23']);

    expect(doc.toString(), equals('''
!!str a: b
c: !!int 42
e: !!str f
g: h
'''));
    expectYamlBuilderValue(doc, {'a': 'b', 'c': 42, 'e': 'f', 'g': 'h'});
  });

  test('detect invalid extra closing bracket', () {
    final doc = YamlEditor('''[ a, b ]''');
    doc.appendToList([], 'c ]');

    expect(doc.toString(), equals('''[ a, b , "c ]"]'''));
    expectYamlBuilderValue(doc, ['a', 'b', 'c ]']);
  });
}
