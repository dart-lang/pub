// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
}
