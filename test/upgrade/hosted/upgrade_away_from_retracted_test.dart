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
}
