// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      'unlocks dependencies if necessary to ensure that a new '
      'dependency is satisfied', () async {
    final server = await servePackages();

    server.serve('foo', '1.0.0', deps: {'bar': '<2.0.0'});
    server.serve('bar', '1.0.0', deps: {'baz': '<2.0.0'});
    server.serve('baz', '1.0.0', deps: {'qux': '<2.0.0'});
    server.serve('qux', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '1.0.0'),
      d.packageConfigEntry(name: 'bar', version: '1.0.0'),
      d.packageConfigEntry(name: 'baz', version: '1.0.0'),
      d.packageConfigEntry(name: 'qux', version: '1.0.0'),
    ]).validate();

    server.serve('foo', '2.0.0', deps: {'bar': '<3.0.0'});
    server.serve('bar', '2.0.0', deps: {'baz': '<3.0.0'});
    server.serve('baz', '2.0.0', deps: {'qux': '<3.0.0'});
    server.serve('qux', '2.0.0');
    server.serve('newdep', '2.0.0', deps: {'baz': '>=1.5.0'});

    await d.appDir(dependencies: {'foo': 'any', 'newdep': 'any'}).create();

    await pubGet();

    await d.appPackageConfigFile([
      d.packageConfigEntry(name: 'foo', version: '2.0.0'),
      d.packageConfigEntry(name: 'bar', version: '2.0.0'),
      d.packageConfigEntry(name: 'baz', version: '2.0.0'),
      d.packageConfigEntry(name: 'qux', version: '1.0.0'),
      d.packageConfigEntry(name: 'newdep', version: '2.0.0'),
    ]).validate();
  });
}
