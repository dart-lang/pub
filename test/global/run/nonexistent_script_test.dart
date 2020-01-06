// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

void main() {
  test('errors if the script does not exist.', () async {
    await servePackages((builder) => builder.serve('foo', '1.0.0', pubspec: {
          'dev_dependencies': {'bar': '1.0.0'}
        }));

    await runPub(args: ['global', 'activate', 'foo']);

    var pub = await pubRun(global: true, args: ['foo:script']);
    expect(
        pub.stderr,
        emits(
            "Could not find ${p.join("bin", "script.dart")} in package foo."));
    await pub.shouldExit(exit_codes.NO_INPUT);
  });
}
