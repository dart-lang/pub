// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('test pub commands with many deps', () async {
    var deps = {};
    await servePackages((builder) {
      for (var i = 0; i < 500; i++) {
        builder.serve('foo$i', '1.0.0');
        deps['foo$i'] = '1.0.0';
      }
    });

    await d.appDir(deps).create();

    await pubGet();
    await pubUpgrade();
  });
}
