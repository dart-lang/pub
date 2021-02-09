// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('can unlock a single package only in upgrade', () async {
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

    // This can't upgrade 'bar'
    await pubUpgrade(args: ['bar']);

    await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.0.0'}).validate();

    // Introducing foo and bar 1.1.0, to show that only 'bar' will be upgraded
    globalPackageServer.add((builder) {
      builder.serve('foo', '1.1.0', deps: {'bar': '<2.0.0'});
      builder.serve('bar', '1.1.0');
    });

    await pubUpgrade(args: ['bar']);
    await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.1.0'}).validate();

    await pubUpgrade();
    await d.appPackagesFile({'foo': '2.0.0', 'bar': '2.0.0'}).validate();
  });
}
