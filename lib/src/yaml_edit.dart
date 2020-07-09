// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// YAML parsing is supported by `package:yaml`, and each time a change is
/// made, the resulting YAML AST is compared against our expected output
/// with deep equality to ensure that the output conforms to our expectations.
///
/// **Example**
/// ```dart
/// import 'package:yaml_edit/yaml_edit.dart';
///
/// void main() {
///  final yamlEditor = YamlEditor('{YAML: YAML}');
///  yamlEditor.update(['YAML'], "YAML Ain't Markup Language");
///  print(yamlEditor);
///  // Expected Output:
///  // {YAML: YAML Ain't Markup Language}
/// }
/// ```
///
/// [1]: https://yaml.org/
library yaml_edit;

export 'yaml_edit/editor.dart';
export 'yaml_edit/equality.dart' show deepEquals;
export 'yaml_edit/source_edit.dart';
export 'yaml_edit/wrap.dart' show wrapAsYamlNode;
