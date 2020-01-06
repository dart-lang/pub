// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('highlights overridden packages', () async {
    await servePackages((builder) => builder.serve('overridden', '1.0.0'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'overridden': 'any'}
      })
    ]).create();

    // Upgrade everything.
    await pubUpgrade(output: RegExp(r'''
Resolving dependencies\.\.\..*
! overridden 1\.0\.0 \(overridden\)
''', multiLine: true));
  });
}
