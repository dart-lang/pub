// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'upgrades a locked pub server package with a new incompatible '
      'constraint', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();
    server.serve('foo', '1.0.1');
    await d.appDir(dependencies: {'foo': '>1.0.0'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.1'),
    ]).validate();
  });
}
