// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('gets packages transitively from a pub server', () async {
    await servePackages()
      ..serve('foo', '1.2.3', deps: {'bar': '2.0.4'})
      ..serve('bar', '2.0.3')
      ..serve('bar', '2.0.4')
      ..serve('bar', '2.0.5');

    await d.appDir(dependencies: {'foo': '1.2.3'}).create();

    await pubGet();

    await d.cacheDir({'foo': '1.2.3', 'bar': '2.0.4'}).validate();
    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.2.3'),
      d.packageConfigEntry(name: 'bar', version: '2.0.4'),
    ]).validate();
  });
}
