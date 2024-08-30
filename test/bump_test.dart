// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart';
import 'test_pub.dart';

void main() {
  void testBump(String part, String from, String to) {
    test('Bumps the $part version from $from to $to', () async {
      await appDir(pubspec: {'version': from}).create();
      await runPub(
        args: ['bump', part, '--dry-run'],
        output: contains('Would update version from $from to $to.'),
      );
      await runPub(
        args: ['bump', part],
        output: contains('Updating version from $from to $to.'),
      );
      await appDir(pubspec: {'version': to}).validate();
    });
  }

  testBump('--major', '0.0.0', '1.0.0');
  testBump('--major', '1.2.3', '2.0.0');
  testBump('--minor', '0.1.1-dev+2', '0.2.0');
  testBump('--minor', '1.2.3', '1.3.0');
  testBump('--patch', '0.1.1-dev+2', '0.1.1');
  testBump('--patch', '0.1.1+2', '0.1.2');
  testBump('--patch', '1.2.3', '1.2.4');
  testBump('--breaking', '0.2.0', '0.3.0');
  testBump('--breaking', '1.2.3', '2.0.0');

  test('Creates top-level version field if missing', () async {
    await dir(appPath, [
      file('pubspec.yaml', '''
name: my_app
'''),
    ]).create();
    await runPub(
      args: ['bump', '--breaking'],
      output: contains('Updating version from 0.0.0 to 0.1.0'),
    );
    await dir(appPath, [
      file('pubspec.yaml', '''
name: my_app
version: 0.1.0
'''),
    ]).create();
  });
}
