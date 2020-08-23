// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('default bump', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(output: contains('1.2.3 to 1.2.4'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.4',
      })
    ]).validate();
  });

  test('bump to version', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(args: ['4.5.6'], output: contains('1.2.3 to 4.5.6'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '4.5.6',
      })
    ]).validate();
  });

  test('bump to version with pre-release and build', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(
        args: ['4.5.6-alpha+build.1'],
        output: contains('1.2.3 to 4.5.6-alpha+build.1'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '4.5.6-alpha+build.1',
      })
    ]).validate();
  });

  test('bump with pre-release', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3-dev',
      })
    ]).create();

    await pubBump(output: contains('1.2.3-dev to 1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).validate();
  });

  test('bump with build', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3+build.1',
      })
    ]).create();

    await pubBump(output: contains('1.2.3+build.1 to 1.2.4'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.4',
      })
    ]).validate();
  });

  test('bump with build and pre-release', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3-alpha+build.1',
      })
    ]).create();

    await pubBump(output: contains('1.2.3-alpha+build.1 to 1.2.3'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).validate();
  });

  test('bump major', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(args: ['--major'], output: contains('1.2.3 to 2.0.0'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '2.0.0',
      })
    ]).validate();
  });

  test('bump minor', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(args: ['--minor'], output: contains('1.2.3 to 1.3.0'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.3.0',
      })
    ]).validate();
  });

  test('bump patch', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.3',
      })
    ]).create();

    await pubBump(output: contains('1.2.3 to 1.2.4'));

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '1.2.4',
      })
    ]).validate();
  });

  group('fails if', () {
    test('more than one flag is provided', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.2.3',
        })
      ]).create();

      await pubBump(
          args: ['--major', '--patch'],
          error: contains('Only one flag should be specified at most'),
          exitCode: exit_codes.USAGE);
    });

    test('a flag is provided along with an argument', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.2.3',
        })
      ]).create();

      await pubBump(
          args: ['--major', '4.5.6'],
          error: contains(
              'Must not specify a version to bump to along with flags'),
          exitCode: exit_codes.USAGE);
    });

    test('more than one argument is provided', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.2.3',
        })
      ]).create();

      await pubBump(
          args: ['4.5.6', '4.5.7'],
          error: contains('Please specify only one version to bump to'),
          exitCode: exit_codes.USAGE);
    });

    test('invalid version to bump to is provided', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'version': '1.2.3',
        })
      ]).create();

      await pubBump(
          args: ['a.b.c'],
          error: contains('Invalid version a.b.c found.'),
          exitCode: exit_codes.USAGE);
    });
  });
}
