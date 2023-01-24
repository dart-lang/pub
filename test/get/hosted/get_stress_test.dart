// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('gets more than 16 packages from a pub server', () async {
    final server = await servePackages();
    server.serve('foo', '1.2.3');
    for (var i = 0; i < 20; i++) {
      server.serve('pkg$i', '1.$i.0');
    }

    await d.appDir(
      dependencies: {
        'foo': '1.2.3',
        for (var i = 0; i < 20; i++) 'pkg$i': '^1.$i.0',
      },
    ).create();

    await pubGet();

    await d.cacheDir({
      'foo': '1.2.3',
      for (var i = 0; i < 20; i++) 'pkg$i': '1.$i.0',
    }).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      for (var i = 0; i < 20; i++)
        d.packageConfigEntry(name: 'pkg$i', version: '1.$i.0')
    ]).validate();
  });
}
