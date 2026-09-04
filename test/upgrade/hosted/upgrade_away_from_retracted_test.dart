// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrade will downgrade if current version is retracted', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0');
    server.serve('foo', '1.5.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet(output: contains('+ foo 1.5.0'));
    server.retractPackageVersion('foo', '1.5.0');
    await pubUpgrade(output: contains('< foo 1.0.0'));
  });

  test('Versions pinned in dependency_overrides are allowed', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0');
    server.serve('foo', '1.5.0');

    await d
        .appDir(
          dependencies: {'foo': '^1.0.0'},
          pubspec: {
            'dependency_overrides': {'foo': '1.5.0'},
          },
        )
        .create();

    await pubGet(output: contains('! foo 1.5.0 (overridden)'));
    server.retractPackageVersion('foo', '1.5.0');
    await pubUpgrade(output: contains('! foo 1.5.0 (overridden) (retracted)'));
  });

  test(
    'upgrade will not downgrade if current version is not unlocked',
    () async {
      final server = await servePackages();

      server.serve('foo', '1.0.0');
      server.serve('foo', '1.5.0');

      server.serve('bar', '1.0.0');
      server.serve('bar', '1.5.0');

      await d.appDir(dependencies: {'foo': '^1.0.0', 'bar': '^1.0.0'}).create();

      await pubGet(
        output: allOf(contains('+ foo 1.5.0'), contains('+ bar 1.5.0')),
      );
      server.retractPackageVersion('foo', '1.5.0');
      server.retractPackageVersion('bar', '1.5.0');

      await pubUpgrade(
        args: ['foo'], // bar stays locked, we are only upgrading foo.
        output: allOf(contains('< foo 1.0.0'), isNot(contains('bar'))),
      );
    },
  );

  test('downgrade will upgrade if current version is retracted', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await pubGet(output: contains('+ foo 1.0.0'));
    server.serve('foo', '1.5.0');

    server.retractPackageVersion('foo', '1.0.0');
    await pubDowngrade(output: contains('> foo 1.5.0'));
  });
}
