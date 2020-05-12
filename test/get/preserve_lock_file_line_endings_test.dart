// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> main() async {
  test('pub get creates lock file with unix line endings if none exist',
      () async {
    await d.appDir().create();

    await pubGet();

    await d
        .file(path.join(appPath, 'pubspec.lock'),
            allOf(contains('\n'), isNot(contains('\r\n'))))
        .validate();
  });

  test('pub get preserves line endings of lock file', () async {
    await d.appDir().create();

    await pubGet();

    final lockFile = d.file(path.join(appPath, 'pubspec.lock')).io;
    lockFile.writeAsStringSync(
        lockFile.readAsStringSync().replaceAll('\n', '\r\n'));
    await d.dir(appPath, [d.file('pubspec.lock', contains('\r\n'))]).validate();

    await pubGet();

    await d.dir(appPath, [d.file('pubspec.lock', contains('\r\n'))]).validate();
  });
}
