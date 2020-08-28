// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('downgrade respects version constraints', () async {
    await servePackages((builder) {
      builder.serve('foo', '2.5.0');
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '1.0.0');
    });

    await d.appDir({'foo': '^2.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '2.5.0'}).validate();

    await pubDowngrade(args: ['foo']);

    await d.cacheDir({'foo': '2.0.0'}).validate();
    await d.appPackagesFile({'foo': '2.0.0'}).validate();
    await d.appDir({'foo': '^2.0.0'}).validate();
  });

  test('downgrade affects transitive dependencies', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.5.0', deps: {'bar': '1.5.0'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.5.0');
    });

    await d.appDir({'foo': '^1.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.5.0', 'bar': '1.5.0'}).validate();

    await pubDowngrade(args: ['foo']);
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.0.0'}).validate();
    await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.0.0'}).validate();
    await d.appDir({'foo': '^1.0.0'}).validate();
  });

  test('downgrade respects transitive dependencies constraints', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'bar': '1.0.0'});
      builder.serve('foo', '1.5.0', deps: {'bar': '1.5.0'});
      builder.serve('bar', '1.0.0');
      builder.serve('bar', '1.5.0');
    });

    await d.appDir({'foo': '^1.0.0', 'bar': '1.5.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.5.0', 'bar': '1.5.0'}).validate();

    await pubDowngrade(args: ['foo']);
    await d.cacheDir({'foo': '1.5.0', 'bar': '1.5.0'}).validate();
    await d.appPackagesFile({'foo': '1.5.0', 'bar': '1.5.0'}).validate();
    await d.appDir({'foo': '^1.0.0', 'bar': '1.5.0'}).validate();
  });

  test('does not downgrade if it is not allowed to', () async {
    await servePackages((builder) {
      builder.serve('foo', '2.0.0');
      builder.serve('foo', '1.0.0');
    });

    await d.appDir({'foo': '^2.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '2.0.0'}).validate();

    await pubDowngrade(args: ['foo']);

    await d.cacheDir({'foo': '2.0.0'}).validate();
    await d.appPackagesFile({'foo': '2.0.0'}).validate();
    await d.appDir({'foo': '^2.0.0'}).validate();
  });

  test('downgrade with package specified does not downgrade other packages',
      () async {
    await servePackages((builder) {
      builder.serve('foo', '1.5.0');
      builder.serve('foo', '1.0.0');
      builder.serve('bar', '1.5.0');
      builder.serve('bar', '1.0.0');
    });

    await d.appDir({'foo': '^1.0.0', 'bar': '^1.0.0'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.5.0', 'bar': '1.5.0'}).validate();

    await pubDowngrade(args: ['foo']);
    await d.cacheDir({'foo': '1.0.0', 'bar': '1.5.0'}).validate();
    await d.appPackagesFile({'foo': '1.0.0', 'bar': '1.5.0'}).validate();
    await d.appDir({'foo': '^1.0.0', 'bar': '^1.0.0'}).validate();
  });
}
