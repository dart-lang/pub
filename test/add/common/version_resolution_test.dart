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
    final server = await servePackages();

    server.serve('foo', '3.2.1');
    server.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});

    await d.appDir(dependencies: {'bar': '1.0.0'}).create();
    await pubGet();

    /// foo's package creator releases a newer version of foo, and we
    /// want to test that this is what the user gets when they run
    /// pub add foo.
    server.serve('foo', '3.5.0');
    server.serve('foo', '3.1.0');
    server.serve('foo', '2.5.0');

    await pubAdd(
      args: ['foo', '--dry-run'],
      output: allOf(
        contains('> foo 3.5.0 (was 3.2.1)'),
      ),
    );
    await pubAdd(args: ['foo']);

    await d.appDir(dependencies: {'foo': '^3.5.0', 'bar': '1.0.0'}).validate();
    await d.cacheDir({'foo': '3.5.0', 'bar': '1.0.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '3.5.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
  });

  test('chooses the appropriate version to not break other dependencies',
      () async {
    /// The server used to only have the foo v3.2.1 as the latest,
    /// so pub get will create a pubspec.lock to foo 3.2.1
    final server = await servePackages();

    server.serve('foo', '3.2.1');
    server.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});

    await d.appDir(dependencies: {'bar': '1.0.0'}).create();
    await pubGet();

    server.serve('foo', '4.0.0');
    server.serve('foo', '2.0.0');

    await pubAdd(args: ['foo']);

    await d.appDir(dependencies: {'foo': '^3.2.1', 'bar': '1.0.0'}).validate();
    await d.cacheDir({'foo': '3.2.1', 'bar': '1.0.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '3.2.1'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
  });

  test('may upgrade other packages if they allow a later version to be chosen',
      () async {
    /// The server used to only have the foo v3.2.1 as the latest,
    /// so pub get will create a pubspec.lock to foo 3.2.1
    final server = await servePackages();

    server.serve('foo', '3.2.1');
    server.serve('bar', '1.0.0', deps: {'foo': '^3.2.1'});

    await d.appDir(dependencies: {'bar': '^1.0.0'}).create();
    await pubGet();

    server.serve('foo', '5.0.0');
    server.serve('foo', '4.0.0');
    server.serve('foo', '2.0.0');
    server.serve('bar', '1.5.0', deps: {'foo': '^4.0.0'});

    await pubAdd(args: ['foo']);

    await d.appDir(dependencies: {'foo': '^4.0.0', 'bar': '^1.0.0'}).validate();
    await d.cacheDir({'foo': '4.0.0', 'bar': '1.5.0'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '4.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.5.0'),
    ]).validate();
  });
}
