// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('performs version solver backtracking if necessary', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.1.0',
        pubspec: {
          'environment': {'sdk': defaultSdkConstraint}
        },
      )
      ..serve(
        'foo',
        '1.2.0',
        pubspec: {
          'environment': {'sdk': '^3.1.3'}
        },
      );

    await runPub(args: ['global', 'activate', 'foo']);

    // foo 1.2.0 won't be picked because its SDK constraint conflicts with the
    // dummy SDK version 3.1.2+3.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [d.file('pubspec.lock', contains('1.1.0'))])
      ])
    ]).validate();
  });
}
