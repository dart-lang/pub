// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('errors if the package is not activated', () async {
    await servePackages();

    await runPub(
      args: ['global', 'deactivate', 'foo'],
      error: 'No active package foo.',
      exitCode: exit_codes.DATA,
    );
  });

  test('errors if the package exists with another casing', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0');
    await runPub(args: ['global', 'activate', 'foo']);
    await runPub(
      args: ['global', 'deactivate', 'Foo'],
      error: 'No active package Foo.',
      exitCode: exit_codes.DATA,
    );
  });
}
