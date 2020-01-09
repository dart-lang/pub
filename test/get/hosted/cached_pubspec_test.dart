// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('does not request a pubspec for a cached package', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({'foo': '1.2.3'}).create();

    // Get once so it gets cached.
    await pubGet();

    // Clear the cache. We don't care about anything that was served during
    // the initial get.
    globalServer.requestedPaths.clear();

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();

    // Run the solver again now that it's cached.
    await pubGet();

    // The get should not have requested the pubspec since it's local already.
    expect(globalServer.requestedPaths,
        isNot(contains('packages/foo/versions/1.2.3.yaml')));
  });
}
