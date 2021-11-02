// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'does not show how many newer versions are available for '
      'packages that are locked and not being upgraded', () async {
    await servePackages((builder) {
      builder.serve('a', '1.0.0');
      builder.serve('b', '1.0.0');
      builder.serve('c', '2.0.0');
    });

    await d.appDir({'a': 'any'}).create();

    // One dependency changed.
    await pubUpgrade(output: RegExp(r'Changed 1 dependency!$'));

    // Remove one and add two.
    await d.appDir({'b': 'any', 'c': 'any'}).create();

    await pubUpgrade(output: RegExp(r'Changed 3 dependencies!$'));

    // Don't change anything.
    await pubUpgrade(output: RegExp(r'No dependencies changed.$'));
  });
}
