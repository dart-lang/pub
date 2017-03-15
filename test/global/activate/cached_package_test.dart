// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('can activate an already cached package', () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0");
    });

    schedulePub(args: ["cache", "add", "foo"]);

    schedulePub(
        args: ["global", "activate", "foo"],
        output: """
        Resolving dependencies...
        + foo 1.0.0
        Precompiling executables...
        Activated foo 1.0.0.""");

    // Should be in global package cache.
    d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [d.matcherFile('pubspec.lock', contains('1.0.0'))])
      ])
    ]).validate();
  });
}
