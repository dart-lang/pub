// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// These tests only work on case-sensitive file systems (ie. only on linux).
@OnPlatform({
  'windows': Skip('Windows file system is case-insensitive'),
  'mac-os': Skip('MacOS file system is case-insensitive')
})

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(error, int exitCode) async {
  await runPub(
    error: error,
    args: ['publish', '--dry-run'],
    workingDirectory: d.path(appPath),
    exitCode: exitCode,
  );
}

late d.DirectoryDescriptor fakeFlutterRoot;

void main() {
  test('Recognizes files that only differ in capitalization.', () async {
    await d.validPackage().create();
    await d.dir(appPath, [d.file('Pubspec.yaml')]).create();
    await expectValidation(
      allOf(
        contains('Package validation found the following error:'),
        contains(
          'The file ./pubspec.yaml and ./Pubspec.yaml only differ in capitalization.',
        ),
      ),
      DATA,
    );
  });
}
