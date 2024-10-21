// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades a locked pub server package with a nonexistent version',
      () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
    ]).validate();

    deleteEntry(p.join(d.sandbox, cachePath));

    server.clearPackages();
    server.serve('foo', '1.0.1');

    await pubGet();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.1'),
    ]).validate();
  });
}
