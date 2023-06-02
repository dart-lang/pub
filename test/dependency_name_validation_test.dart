// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import 'descriptor.dart';
import 'test_pub.dart';

void main() {
  test('Dependency names have to be valid package names', () async {
    await appDir(dependencies: {'abc def': '1.0.0'}).create();
    await pubGet(error: contains('Not a valid package name.'), exitCode: DATA);
  });

  test('Dev-dependency names have to be valid package names', () async {
    await appDir(
      pubspec: {
        'dev_dependencies': {'abc def': '1.0.0'}
      },
    ).create();
    await pubGet(error: contains('Not a valid package name.'), exitCode: DATA);
  });
}
