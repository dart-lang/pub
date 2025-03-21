// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--dry-run shows but does not apply changes', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();

    await pubGet(
      args: ['--dry-run'],
      output: allOf([
        contains('+ foo 1.0.0'),
        contains('Would change 1 dependency.'),
      ]),
    );

    await d.dir(appPath, [
      d.nothing('pubspec.lock'),
      d.nothing('.dart_tool/package_config.json'),
    ]).validate();
  });
}
