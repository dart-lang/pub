// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/entrypoint.dart';
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

  test('windows line endings detection', () {
    expect(detectWindowsLineEndings(''), false);
    expect(detectWindowsLineEndings('\n'), false);
    expect(detectWindowsLineEndings('\r'), false);
    expect(detectWindowsLineEndings('\r\n'), true);
    expect(detectWindowsLineEndings('\n\r\n'), false);
    expect(detectWindowsLineEndings('\r\n\n'), false);
    expect(detectWindowsLineEndings('\r\n\r\n'), true);
    expect(detectWindowsLineEndings('\n\n'), false);
    expect(detectWindowsLineEndings('abcd\n'), false);
    expect(detectWindowsLineEndings('abcd\nefg'), false);
    expect(detectWindowsLineEndings('abcd\nefg\n'), false);
    expect(detectWindowsLineEndings('\r\n'), true);
    expect(detectWindowsLineEndings('abcd\r\nefg\n'), false);
    expect(detectWindowsLineEndings('abcd\r\nefg\nhij\r\n'), true);
    expect(detectWindowsLineEndings('''
packages:\r
  bar:\r
    dependency: transitive\r
    description: "bar desc"\r
    source: fake\r
    version: "1.2.3"\r
sdks: {}\r
'''), true);
    expect(detectWindowsLineEndings('''
packages:
  bar:
    dependency: transitive
    description: "bar desc"
    source: fake
    version: "1.2.3"
sdks: {}
'''), false);
  });
}
