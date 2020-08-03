// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

void main() {
  test('my test', () {
    final doc = YamlEditor('''
a: 
  - b
  - c
''');
    doc.remove(['a', 0]);
    expect(doc.toString(), equals('''
a: 
  - c
'''));
  });
}
