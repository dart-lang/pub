// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run mentions that checks are not exhaustive', () async {
    await d.validPackage().create();
    await runPub(
      args: ['publish', '--dry-run'],
      output: contains('The server may enforce additional checks.'),
    );
  });
}
