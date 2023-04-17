// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      "upgrades one locked pub server package's dependencies if it's "
      'necessary', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0');
    server.serve('foo', '1.1.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.1.0'),
    ]).validate();

    server.retractPackageVersion('foo', '1.1.0');

    await pubUpgrade();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();
  });
}
