// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

void main() {
  group('YamlEditor records edits', () {
    test('returns empty list at start', () {
      final yamlEditor = YamlEditor('YAML: YAML');

      expect(yamlEditor.edits, []);
    });

    test('after one change', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.update(['YAML'], "YAML Ain't Markup Language");

      expect(
          yamlEditor.edits, [SourceEdit(5, 5, " YAML Ain't Markup Language")]);
    });

    test('after multiple changes', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.update(['YAML'], "YAML Ain't Markup Language");
      yamlEditor.update(['XML'], 'Extensible Markup Language');
      yamlEditor.remove(['YAML']);

      expect(yamlEditor.edits, [
        SourceEdit(5, 5, " YAML Ain't Markup Language"),
        SourceEdit(0, 0, 'XML: Extensible Markup Language\n'),
        SourceEdit(31, 33, '')
      ]);
    });

    test('that do not automatically update with internal list', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.update(['YAML'], "YAML Ain't Markup Language");

      final firstEdits = yamlEditor.edits;

      expect(firstEdits, [SourceEdit(5, 5, " YAML Ain't Markup Language")]);

      yamlEditor.update(['XML'], 'Extensible Markup Language');
      yamlEditor.remove(['YAML']);

      expect(firstEdits, [SourceEdit(5, 5, " YAML Ain't Markup Language")]);
      expect(yamlEditor.edits, [
        SourceEdit(5, 5, " YAML Ain't Markup Language"),
        SourceEdit(0, 0, 'XML: Extensible Markup Language\n'),
        SourceEdit(31, 33, '')
      ]);
    });
  });
}
