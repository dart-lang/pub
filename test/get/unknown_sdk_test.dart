// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get barks at unknown sdk', () async {
    await d.dir(appPath, [
      d.pubspec({
        'environment': {'foo': '>=1.2.4 <2.0.0'}
      })
    ]).create();

    await pubGet(
      error: contains(
        "Error on line 1, column 32 of pubspec.yaml: pubspec.yaml refers to an unknown sdk 'foo'.",
      ),
      exitCode: exit_codes.DATA,
    );
  });
}
