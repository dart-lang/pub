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
      builder.serve('not_upgraded', '1.0.0');
      builder.serve('not_upgraded', '2.0.0');
      builder.serve('not_upgraded', '3.0.0-dev');
      builder.serve('upgraded', '1.0.0');
      builder.serve('upgraded', '2.0.0');
      builder.serve('upgraded', '3.0.0-dev');
    });

    // Constraint everything to the first version.
    await d.appDir({'not_upgraded': '1.0.0', 'upgraded': '1.0.0'}).create();

    await pubGet();

    // Loosen the constraints.
    await d.appDir({'not_upgraded': 'any', 'upgraded': 'any'}).create();

    // Only upgrade "upgraded".
    await pubUpgrade(args: ['upgraded'], output: RegExp(r'''
Resolving dependencies\.\.\..*
  not_upgraded 1\.0\.0
. upgraded 2\.0\.0 \(was 1\.0\.0\) \(3\.0\.0-dev available\)
''', multiLine: true), environment: {'PUB_ALLOW_PRERELEASE_SDK': 'false'});
  });
}
