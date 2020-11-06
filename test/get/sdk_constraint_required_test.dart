// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get fails without an SDK constraint', () async {
    await d.dir(appPath, [
      d.rawPubspec({
        'name': 'myapp',
      }),
    ]).create();

    await pubGet(
        error: contains('pubspec.yaml has no lower-bound SDK constraint.'),
        exitCode: exit_codes.DATA);

    await d.dir(appPath, [
      // The lockfile should not be created.
      d.nothing('pubspec.lock'),
      // The "packages" directory should not have been generated.
      d.nothing('packages'),
      // The ".packages" file should not have been created.
      d.nothing('.packages'),
    ]).validate();
  });
}
