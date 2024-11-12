// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart';
import '../golden_file.dart';
import '../test_pub.dart';

Future<void> main() async {
  testWithGolden('Layout of publication warnings', (ctx) async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    server.serve('bar', '1.0.0');

    await dir(appPath, [
      pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.0.0'},
        'dependencies': {'bar': null},
        'dependency_overrides': {'bar': '1.0.0'},
      }),
      dir('bin', [
        file('main.dart', '''
import 'package:foo/foo.dart';
'''),
      ]),
    ]).create();
    await ctx.run(
      ['publish', '--dry-run'],
      environment: {
        // Use more columns to avoid unintended line breaking.
        '_PUB_TEST_TERMINAL_COLUMNS': '200',
      },
    );
  });
}
