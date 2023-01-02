// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades dependencies whose constraints have been removed', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'shared_dep': 'any'})
      ..serve('bar', '1.0.0', deps: {'shared_dep': '<2.0.0'})
      ..serve('shared_dep', '1.0.0')
      ..serve('shared_dep', '2.0.0');

    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();

    await pubUpgrade();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
      d.packageConfigEntry(name: 'shared_dep', version: '1.0.0'),
    ]).validate();

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubUpgrade();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'shared_dep', version: '2.0.0'),
    ]).validate();
  });
}
