// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('performs verison solver backtracking if necessary', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.1.0', pubspec: {
        'environment': {'sdk': '>=0.1.2 <0.2.0'}
      });
      builder.serve('foo', '1.2.0', pubspec: {
        'environment': {'sdk': '>=0.1.3 <0.2.0'}
      });
    });

    await runPub(args: ['global', 'activate', 'foo']);

    // foo 1.2.0 won't be picked because its SDK constraint conflicts with the
    // dummy SDK version 0.1.2+3.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [d.file('pubspec.lock', contains('1.1.0'))])
      ])
    ]).validate();
  });
}
