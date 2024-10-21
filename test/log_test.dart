// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/log.dart';
import 'package:test/test.dart';

void main() {
  test('limitLength', () {
    expect(limitLength('', 7), '');
    expect(limitLength('x', 7), 'x');
    expect(limitLength('x' * 7, 7), 'x' * 7);
    expect(limitLength('x' * 8, 7), 'x[...]x');
    expect(limitLength('x' * 1000, 7), 'x[...]x');
    expect(limitLength('', 8), '');
    expect(limitLength('x', 8), 'x');
    expect(limitLength('x' * 8, 8), 'x' * 8);
    expect(limitLength('x' * 9, 8), 'xx[...]x');
    expect(limitLength('x' * 1000, 8), 'xx[...]x');
  });
}
