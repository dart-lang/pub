// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('can unlock a single package only in downgrade', () async {
    final server = await servePackages();
    server.serve('foo', '2.1.0', deps: {'bar': '>1.0.0'});
    server.serve('bar', '2.1.0');

    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();

    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.1.0'),
      d.packageConfigEntry(name: 'bar', version: '2.1.0'),
    ]).validate();

    server.serve('foo', '1.0.0', deps: {'bar': 'any'});
    server.serve('bar', '1.0.0');

    await pubDowngrade(args: ['bar']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.1.0'),
      d.packageConfigEntry(name: 'bar', version: '2.1.0'),
    ]).validate();

    server.serve('foo', '2.0.0', deps: {'bar': 'any'});
    server.serve('bar', '2.0.0');

    await pubDowngrade(args: ['bar']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.1.0'),
      d.packageConfigEntry(name: 'bar', version: '2.0.0'),
    ]).validate();

    await pubDowngrade();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
  });

  test('will not downgrade below constraint #2629', () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
      ..serve('foo', '2.1.0');

    await d.appDir(dependencies: {'foo': '^2.0.0'}).create();

    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.1.0'),
    ]).validate();

    await pubDowngrade(args: ['foo']);

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.0.0'),
    ]).validate();
  });
}
