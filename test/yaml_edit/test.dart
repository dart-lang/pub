// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

void main() {
  test('', () {
    final doc = YamlEditor(
        '''{ 0.7496231834381617: 0.04661042576927199, "G:dv%G=I'Qpxno9t?e]V6,~eNvQy(4]": false, false: 271637351, null: {}}''');
    doc.update([745263179], ['!!%v*']);
    print(doc);
  });
}
