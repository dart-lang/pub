// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('does not request versions if the lockfile is up to date', () async {
    final server =
        await servePackages()
          ..serve('foo', '1.0.0')
          ..serve('foo', '1.1.0')
          ..serve('foo', '1.2.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    // Get once so it gets cached.
    await pubGet();

    // Clear the cache. We don't care about anything that was served during
    // the initial get.
    server.requestedPaths.clear();

    // Run the solver again now that it's cached.
    await pubGet();

    await d.cacheDir({'foo': '1.2.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.0'),
    ]).validate();

    // The get should not have done any network requests since the lock file is
    // up to date.
    expect(server.requestedPaths, isEmpty);
  });
}
