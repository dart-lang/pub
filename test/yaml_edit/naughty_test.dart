// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:pub/src/yaml_edit/yaml_edit.dart';

import 'problem_strings.dart';

void main() {
  for (var string in problemStrings) {
    test('expect string $string', () {
      final doc = YamlEditor('');

      expect(() => doc.update([], string), returnsNormally);
      final value = doc.parseAt([]).value;
      expect(value, isA<String>());
      expect(value, equals(string));
    });
  }
}
