// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('does nothing if the package is already cached', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.3');
    });

    // Run once to put it in the cache.
    await runPub(
        args: ['cache', 'add', 'foo'], output: 'Downloading foo 1.2.3...');

    // Should be in the cache now.
    await runPub(
        args: ['cache', 'add', 'foo'], output: 'Already cached foo 1.2.3.');

    await d.cacheDir({'foo': '1.2.3'}).validate();
  });
}
