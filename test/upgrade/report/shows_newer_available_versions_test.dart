// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('shows how many newer versions are available', () async {
    await servePackages()
      ..serve('multiple_newer', '1.0.0')
      ..serve('multiple_newer', '1.0.1-unstable.1')
      ..serve('multiple_newer', '1.0.1')
      ..serve('multiple_newer', '1.0.2-unstable.1')
      ..serve('multiple_newer_stable', '1.0.0')
      ..serve('multiple_newer_stable', '1.0.1')
      ..serve('multiple_newer_stable', '1.0.2')
      ..serve('multiple_newer_unstable', '1.0.0')
      ..serve('multiple_newer_unstable', '1.0.1-unstable.1')
      ..serve('multiple_newer_unstable', '1.0.1-unstable.2')
      ..serve('multiple_newer_unstable2', '1.0.1-unstable.1')
      ..serve('multiple_newer_unstable2', '1.0.1-unstable.2')
      ..serve('no_newer', '1.0.0')
      ..serve('one_newer_unstable', '1.0.0')
      ..serve('one_newer_unstable', '1.0.1-unstable.1')
      ..serve('one_newer_unstable2', '1.0.1-unstable.1')
      ..serve('one_newer_unstable2', '1.0.1-unstable.2')
      ..serve('one_newer_stable', '1.0.0')
      ..serve('one_newer_stable', '1.0.1');

    // Constraint everything to the first version.
    await d.appDir(
      dependencies: {
        'multiple_newer': '1.0.0',
        'multiple_newer_stable': '1.0.0',
        'multiple_newer_unstable': '1.0.0',
        'multiple_newer_unstable2': '1.0.1-unstable.1',
        'no_newer': '1.0.0',
        'one_newer_unstable': '1.0.0',
        'one_newer_unstable2': '1.0.1-unstable.1',
        'one_newer_stable': '1.0.0'
      },
    ).create();

    // Upgrade everything.
    await pubUpgrade(
      output: RegExp(
        r'''
Resolving dependencies\.\.\..*
. multiple_newer 1\.0\.0 \(1\.0\.1 available\)
. multiple_newer_stable 1\.0\.0 \(1\.0\.2\ available\)
. multiple_newer_unstable 1\.0\.0
. multiple_newer_unstable2 1\.0\.1-unstable\.1 \(1\.0\.1-unstable\.2 available\)
. no_newer 1\.0\.0
. one_newer_stable 1\.0\.0 \(1\.0\.1 available\)
. one_newer_unstable 1\.0\.0
. one_newer_unstable2 1\.0\.1-unstable\.1 \(1\.0\.1-unstable\.2 available\)
''',
        multiLine: true,
      ),
      environment: {'PUB_ALLOW_PRERELEASE_SDK': 'false'},
    );
  });
}
