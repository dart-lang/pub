// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('only requests versions that are needed during solving', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '1.1.0');
      builder.serve('foo', '1.2.0');
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.1.0');
      builder.serve('bar', '1.2.0');
    });

    await d.appDir({'foo': 'any'}).create();

    // Get once so it gets cached.
    await pubGet();

    // Clear the cache. We don't care about anything that was served during
    // the initial get.
    globalServer.requestedPaths.clear();

    // Add "bar" to the dependencies.
    await d.appDir({'foo': 'any', 'bar': 'any'}).create();

    // Run the solver again.
    await pubGet();

    await d.appPackagesFile({'foo': '1.2.0', 'bar': '1.2.0'}).validate();

    // The get should not have done any network requests since the lock file is
    // up to date.
    expect(
        globalServer.requestedPaths,
        unorderedEquals([
          // Bar should be requested because it's new, but not foo.
          'api/packages/bar',
          // Need to download it.
          'packages/bar/versions/1.2.0.tar.gz'
        ]));
  });
}
