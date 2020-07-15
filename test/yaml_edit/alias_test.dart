// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// This test suite is a temporary measure until we are able to better handle
/// aliases.
void main() {
  group('list ', () {
    test('removing an alias anchor results in AliasError', () {
      final doc = YamlEditor('''
- &SS Sammy Sosa
- *SS
''');

      expect(() => doc.remove([0]), throwsAliasError);
    });

    test('removing an alias reference results in AliasError', () {
      final doc = YamlEditor('''
- &SS Sammy Sosa
- *SS
''');

      expect(() => doc.remove([1]), throwsAliasError);
    });

    test('it is okay to remove a non-alias node', () {
      final doc = YamlEditor('''
- &SS Sammy Sosa
- *SS
- Sammy Sosa
''');

      doc.remove([2]);
      expect(doc.toString(), equals('''
- &SS Sammy Sosa
- *SS
'''));
    });
  });

  group('map', () {
    test('removing an alias anchor value results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: *SS
''');

      expect(() => doc.remove(['a']), throwsAliasError);
    });

    test('removing an alias reference value results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: *SS
''');

      expect(() => doc.remove(['b']), throwsAliasError);
    });

    test('removing an alias anchor key results in AliasError', () {
      final doc = YamlEditor('''
&SS Sammy Sosa: a
b: *SS
''');

      expect(() => doc.remove(['Sammy Sosa']), throwsAliasError);
    });

    test('removing an alias reference key results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
*SS : b
''');

      expect(() => doc.remove(['Sammy Sosa']), throwsAliasError);
    });

    test('it is okay to remove a non-alias node', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: *SS
c: Sammy Sosa
''');

      doc.remove(['c']);
      expect(doc.toString(), equals('''
a: &SS Sammy Sosa
b: *SS
'''));
    });
  });

  group('nested alias', () {
    test('nested list alias anchors are detected too', () {
      final doc = YamlEditor('''
- 
  - &SS Sammy Sosa
- *SS
''');

      expect(() => doc.remove([0]), throwsAliasError);
    });

    test('nested list alias references are detected too', () {
      final doc = YamlEditor('''
- &SS Sammy Sosa
- 
  - *SS
''');

      expect(() => doc.remove([1]), throwsAliasError);
    });

    test('removing nested map alias anchor results in AliasError', () {
      final doc = YamlEditor('''
a: 
  c: &SS Sammy Sosa
b: *SS
''');

      expect(() => doc.remove(['a']), throwsAliasError);
    });

    test('removing nested map alias reference results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: 
  c: *SS
''');

      expect(() => doc.remove(['b']), throwsAliasError);
    });
  });
}
