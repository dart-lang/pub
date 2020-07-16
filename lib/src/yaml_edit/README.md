# Yaml Editor

A library for [YAML](https://yaml.org) manipulation while preserving comments.

## Usage

A simple usage example:

```dart
import 'package:yaml_edit/yaml_edit.dart';

void main() {
  final yamlEditor = YamlEditor('{YAML: YAML}');
  yamlEditor.assign(['YAML'], "YAML Ain't Markup Language");
  print(yamlEditor);
  // Expected output:
  // {YAML: YAML Ain't Markup Language}
}
```

## Testing

Testing is done in two strategies: Unit testing (`/test/editor_test.dart`) and
Golden testing (`/test/golden_test.dart`). More information on Golden testing
and the input/output format can be found at `/test/testdata/README.md`.

These tests are automatically run with `pub run test`.

## Limitations

1. Users are not allowed to define tags in the modifications.
2. Map keys will always be added in the flow style.
