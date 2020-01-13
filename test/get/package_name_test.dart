// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get fails with a non-identifier name', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'invalid package name', 'version': '1.0.0'})
    ]).create();

    await pubGet(
        error: contains('"name" field must be a valid Dart identifier.'),
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

  test('pub get fails with a reserved word name', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'return', 'version': '1.0.0'})
    ]).create();

    await pubGet(
        error: contains('"name" field may not be a Dart reserved word.'),
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

  test('pub get allows a name with dotted identifiers', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'foo.bar.baz', 'version': '1.0.0'}),
      d.libDir('foo.bar.baz', 'foo.bar.baz 1.0.0')
    ]).create();

    await pubGet();

    await d.dir(appPath, [
      d.packagesFile({'foo.bar.baz': '.'}),
    ]).validate();
  });
}
