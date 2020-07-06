import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';

void main() {
  group('indentation', () {
    test('returns 2 for empty strings', () {
      final doc = YamlEditor('');
      expect(doc.indentation, equals(2));
    });

    test('returns 2 for strings consisting only scalars', () {
      final doc = YamlEditor('foo');
      expect(doc.indentation, equals(2));
    });

    test('returns 2 if only top-level elements are present', () {
      final doc = YamlEditor('''
- 1
- 2
- 3''');
      expect(doc.indentation, equals(2));
    });

    test('detects the indentation used in nested list', () {
      final doc = YamlEditor('''
- 1
- 2
- 
   - 3
   - 4''');
      expect(doc.indentation, equals(3));
    });

    test('detects the indentation used in nested map', () {
      final doc = YamlEditor('''
a: 1
b: 2
c:
   d: 4
   e: 5''');
      expect(doc.indentation, equals(3));
    });

    test('detects the indentation used in nested map in list', () {
      final doc = YamlEditor('''
- 1
- 2
- 
    d: 4
    e: 5''');
      expect(doc.indentation, equals(4));
    });

    test('detects the indentation used in nested map in list with complex keys',
        () {
      final doc = YamlEditor('''
- 1
- 2
- 
    ? d
    : 4''');
      expect(doc.indentation, equals(4));
    });

    test('detects the indentation used in nested list in map', () {
      final doc = YamlEditor('''
a: 1
b: 2
c:
  - 4
  - 5''');
      expect(doc.indentation, equals(2));
    });
  });
  group('YamlEditor records edits', () {
    test('returns empty list at start', () {
      final yamlEditor = YamlEditor('YAML: YAML');

      expect(yamlEditor.edits, []);
    });

    test('after one change', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.assign(['YAML'], "YAML Ain't Markup Language");

      expect(
          yamlEditor.edits, [SourceEdit(5, 5, " YAML Ain't Markup Language")]);
    });

    test('after multiple changes', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.assign(['YAML'], "YAML Ain't Markup Language");
      yamlEditor.assign(['XML'], 'Extensible Markup Language');
      yamlEditor.remove(['YAML']);

      expect(yamlEditor.edits, [
        SourceEdit(5, 5, " YAML Ain't Markup Language"),
        SourceEdit(0, 0, 'XML: Extensible Markup Language\n'),
        SourceEdit(31, 33, '')
      ]);
    });

    test('that do not automatically update with internal list', () {
      final yamlEditor = YamlEditor('YAML: YAML');
      yamlEditor.assign(['YAML'], "YAML Ain't Markup Language");

      final firstEdits = yamlEditor.edits;

      expect(firstEdits, [SourceEdit(5, 5, " YAML Ain't Markup Language")]);

      yamlEditor.assign(['XML'], 'Extensible Markup Language');
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
