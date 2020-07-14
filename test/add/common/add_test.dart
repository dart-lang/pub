// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('adds a package from a pub server', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({}).create();

    await pubAdd(args: ['foo:1.2.3']);

    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.appPackagesFile({'foo': '1.2.3'}).validate();
    await d.appDir({'foo': '1.2.3'}).validate();
  });

  test('URL encodes the package name', () async {
    await serveNoPackages();

    await d.appDir({}).create();

    await pubAdd(
        args: ['bad name!:1.2.3'],
        error: allOf([
          contains(
              "Because myapp depends on bad name! any which doesn't exist (could "
              'not find package bad name! at http://localhost:'),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.UNAVAILABLE);

    await d.appDir({}).validate();
  });

  test('--dev adds packages to dev_dependencies instead', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
    ]).create();

    await pubAdd(args: ['--dev', 'foo:1.2.3']);

    await d.appPackagesFile({'foo': '1.2.3'}).validate();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.2.3'}
      })
    ]).validate();
  });
}
