// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--tighten will set lower bounds to the actually achieved version',
      () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
      ) // Because of the bar constraint, this is not achievable.
      ..serve('foo', '2.0.0')
      ..serve('foo', '3.0.0')
      ..serve('bar', '1.0.0', deps: {'foo': '>=2.0.0'});

    await d.appDir(dependencies: {'foo': '>=1.0.0', 'bar': '^1.0.0'}).create();

    await pubGet(output: contains('foo 3.0.0'));
    await pubDowngrade(
      args: ['--tighten'],
      output: allOf(
        contains('< foo 2.0.0 (was 3.0.0)'),
        contains('foo: >=1.0.0 -> >=2.0.0'),
      ),
    );
  });
}
