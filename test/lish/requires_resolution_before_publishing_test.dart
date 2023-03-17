// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('does not publish if no resolution can be found', () async {
    await servePackages(); // No packages.
    await d.validPackage().create();
    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await runPub(
      args: ['lish'],
      error: contains("Because myapp depends on foo any which doesn't exist"),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });
}
