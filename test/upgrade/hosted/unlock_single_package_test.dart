// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('can unlock a single package only in upgrade', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0', deps: {'bar': '<2.0.0'});
    server.serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();

    server.serve('foo', '2.0.0', deps: {'bar': '<3.0.0'});
    server.serve('bar', '2.0.0');

    // This can't upgrade 'bar'
    await pubUpgrade(args: ['bar']);

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
    ]).validate();
    // Introducing foo and bar 1.1.0, to show that only 'bar' will be upgraded
    server.serve('foo', '1.1.0', deps: {'bar': '<2.0.0'});
    server.serve('bar', '1.1.0');

    await pubUpgrade(args: ['bar']);
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.1.0'),
    ]).validate();
    await pubUpgrade();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.0.0'),
      d.packageConfigEntry(name: 'bar', version: '2.0.0'),
    ]).validate();
  });
}
