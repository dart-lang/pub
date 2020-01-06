// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('installs and activates the best version of a package', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '1.2.3');
      builder.serve('foo', '2.0.0-wildly.unstable');
    });

    await runPub(args: ['global', 'activate', 'foo'], output: '''
        Resolving dependencies...
        + foo 1.2.3 (2.0.0-wildly.unstable available)
        Downloading foo 1.2.3...
        Precompiling executables...
        Activated foo 1.2.3.''');

    // Should be in global package cache.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [d.file('pubspec.lock', contains('1.2.3'))])
      ])
    ]).validate();
  });
}
