// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../../descriptor.dart';
import '../../test_pub.dart';

void main() {
  test('activating an invalid package name fails nicely', () async {
    await appDir().create();
    await runPub(
      args: ['global', 'activate', '.'],
      error: allOf(
        contains('Not a valid package name: "."'),
        contains('Did you mean `dart pub global activate --source path .'),
      ),
      exitCode: USAGE,
    );
  });
}
