import 'package:pub/src/yaml_edit.dart';
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
    test('removing an alias anchor results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: *SS
''');

      expect(() => doc.remove(['a']), throwsAliasError);
    });

    test('removing an alias reference results in AliasError', () {
      final doc = YamlEditor('''
a: &SS Sammy Sosa
b: *SS
''');

      expect(() => doc.remove(['b']), throwsAliasError);
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
