// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('errors if the package could not be found', () async {
    await serveNoPackages();

    await runPub(
        args: ['global', 'activate', 'foo'],
        error: allOf([
          contains(
              "Because pub global activate depends on foo any which doesn't "
              'exist (could not find package foo at http://localhost:'),
          contains('), version solving failed.')
        ]),
        exitCode: exit_codes.UNAVAILABLE);
  });
}
