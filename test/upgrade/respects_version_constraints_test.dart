// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('upgrade respects version constraints', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    await d.appDir({'foo': '^1.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0'}).validate();

    globalPackageServer.add((builder) {
      builder.serve('foo', '1.5.0');
      builder.serve('foo', '2.0.0');
    });

    await pubUpgrade(args: ['foo']);
    await d.cacheDir({'foo': '1.5.0'}).validate();
    await d.appPackagesFile({'foo': '1.5.0'}).validate();
    await d.appDir({'foo': '^1.0.0'}).validate();
  });

  test(
      'upgrade respects version constraints and does not upgrade if impossible',
      () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
    });

    await d.appDir({'foo': '^1.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0'}).validate();

    await pubUpgrade(args: ['foo']);
    await d.cacheDir({'foo': '1.0.0'}).validate();
    await d.appPackagesFile({'foo': '1.0.0'}).validate();
    await d.appDir({'foo': '^1.0.0'}).validate();
  });
}
