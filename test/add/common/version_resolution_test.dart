// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

/// This test suite attempts to cover the edge cases of version resolution
/// with regards to transitive dependencies.
void main() {
  test('unlocks transitive dependencies', () async {
    /// The server used to only have the foo v3.2.1 as the latest,
    /// so pub get will create a pubspec.lock to foo 3.2.1
    await servePackages((builder) {
      builder.serve('foo', '3.2.1');
      builder.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});
    });

    await d.appDir({'bar': '1.0.0'}).create();
    await pubGet();

    /// foo's package creator releases a newer version of foo, and we
    /// want to test that this is what the user gets when they run
    /// pub add foo.
    globalPackageServer.add((builder) {
      builder.serve('foo', '3.5.0');
      builder.serve('foo', '3.1.0');
      builder.serve('foo', '2.5.0');
    });

    await pubAdd(args: ['foo']);

    await d.appDir({'foo': '^3.5.0', 'bar': '1.0.0'}).validate();
    await d.cacheDir({'foo': '3.5.0', 'bar': '1.0.0'}).validate();
    await d.appPackagesFile({'foo': '3.5.0', 'bar': '1.0.0'}).validate();
  });

  test('chooses the appropriate version to not break other dependencies',
      () async {
    /// The server used to only have the foo v3.2.1 as the latest,
    /// so pub get will create a pubspec.lock to foo 3.2.1
    await servePackages((builder) {
      builder.serve('foo', '3.2.1');
      builder.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});
    });

    await d.appDir({'bar': '1.0.0'}).create();
    await pubGet();

    globalPackageServer.add((builder) {
      builder.serve('foo', '4.0.0');
      builder.serve('foo', '2.0.0');
    });

    await pubAdd(args: ['foo']);

    await d.appDir({'foo': '^3.2.1', 'bar': '1.0.0'}).validate();
    await d.cacheDir({'foo': '3.2.1', 'bar': '1.0.0'}).validate();
    await d.appPackagesFile({'foo': '3.2.1', 'bar': '1.0.0'}).validate();
  });

  test('may upgrade other packages if they allow a later version to be chosen',
      () async {
    /// The server used to only have the foo v3.2.1 as the latest,
    /// so pub get will create a pubspec.lock to foo 3.2.1
    await servePackages((builder) {
      builder.serve('foo', '3.2.1');
      builder.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});
    });

    await d.appDir({'bar': '^1.0.0'}).create();
    await pubGet();

    globalPackageServer.add((builder) {
      builder.serve('foo', '5.0.0');
      builder.serve('foo', '4.0.0');
      builder.serve('foo', '2.0.0');
      builder.serve('bar', '1.5.0', deps: {'foo': '^4.0.0'});
    });

    await pubAdd(args: ['foo']);

    await d.appDir({'foo': '^4.0.0', 'bar': '^1.0.0'}).validate();
    await d.cacheDir({'foo': '4.0.0', 'bar': '1.5.0'}).validate();
    await d.appPackagesFile({'foo': '4.0.0', 'bar': '1.5.0'}).validate();
  });
}
