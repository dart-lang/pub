// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('does not show how many other versions are available', () async {
    await servePackages((builder) {
      builder.serve('downgraded', '1.0.0');
      builder.serve('downgraded', '2.0.0');
      builder.serve('downgraded', '3.0.0-dev');
    });

    await d.appDir({'downgraded': '3.0.0-dev'}).create();

    await pubGet();

    // Loosen the constraints.
    await d.appDir({'downgraded': '>=2.0.0'}).create();

    await pubDowngrade(output: contains('downgraded 2.0.0 (was 3.0.0-dev)'));
  });
}
