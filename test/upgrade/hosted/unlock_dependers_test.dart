// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      "upgrades a locked package's dependers in order to get it to max "
      'version', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '<2.0.0'});
      builder.serve('bar', '1.0.0');
    });

    await d.appDir({'foo': 'any', 'bar': 'any'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.0.0'}).validate();

    globalPackageServer.add((builder) {
      builder.serve('foo', '2.0.0', deps: {'bar': '<3.0.0'});
      builder.serve('bar', '2.0.0');
    });

    await pubUpgrade(args: ['bar']);

    await d.appPackagesFile({'foo': '2.0.0', 'bar': '2.0.0'}).validate();
  });
}
