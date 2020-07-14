// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

// import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('removes a package from dependencies', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.appDir({'foo': '1.2.3'}).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackagesFile({}).validate();
    await d.appDir({}).validate();
  });

  test('removes a package from dev_dependencies', () async {
    await servePackages((builder) => builder.serve('foo', '1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.2.3'}
      })
    ]).create();
    await pubGet();

    await pubRemove(args: ['foo']);

    await d.cacheDir({}).validate();
    await d.appPackagesFile({}).validate();

    await d.dir(appPath, [
      d.pubspec({'name': 'myapp', 'dev_dependencies': {}})
    ]).validate();
  });

  test('no-op if package does not exist', () async {
    await d.appDir({}).create();
    await pubRemove(args: ['bar']);

    await d.appDir({}).validate();
  });

  test('removes git dependencies', () async {
    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git', 'path': 'sub/dir', 'ref': 'development'}
      }
    }).create();

    await pubRemove(args: ['foo']);

    await d.appDir({}).validate();
  });
}
