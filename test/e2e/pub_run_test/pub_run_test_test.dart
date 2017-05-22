// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
@TestOn('browser')
import 'package:test/test.dart';

import 'hello.dart';

main() {
  test('hello world', () {
    expect(hello, equals('Hello'));
  });
}
