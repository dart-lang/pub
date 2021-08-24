// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.11

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub upgrade --major-versions does not update dependencies in example/',
      () async {
    await servePackages((b) => b
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0'));
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'bar': '^1.0.0'}
      }),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'dependencies': {
            'bar': '',
            'myapp': {'path': '..'}
          }
        })
      ])
    ]).create();

    await pubUpgrade(
      args: ['--major-versions'],
      output: '''
Resolving dependencies...
+ bar 2.0.0
Downloading bar 2.0.0...
Changed 1 dependency!

Changed 1 constraint in pubspec.yaml:
  bar: ^1.0.0 -> ^2.0.0''',
      warning:
          'Running `upgrade --major-versions` only in `.`. Run in `example/` separately.',
    );
  });

  test('pub upgrade --null-safety does not update dependencies in example/',
      () async {
    await servePackages((b) => b
      ..serve('bar', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.7.0 <3.0.0'},
      })
      ..serve('bar', '2.0.0', pubspec: {
        'environment': {'sdk': '>=2.12.0 <3.0.0'},
      }));
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'bar': '^1.0.0'},
        'environment': {'sdk': '>=2.7.0 <3.0.0'},
      }),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'environment': {'sdk': '>=2.7.0 <3.0.0'},
          'dependencies': {
            'bar': '1.0.0',
            'myapp': {'path': '..'}
          }
        })
      ])
    ]).create();

    await pubUpgrade(
        args: ['--null-safety'],
        output: '''
Resolving dependencies...
+ bar 2.0.0
Downloading bar 2.0.0...
Changed 1 dependency!

Changed 1 constraint in pubspec.yaml:
  bar: ^1.0.0 -> ^2.0.0''',
        warning:
            'Running `upgrade --null-safety` only in `.`. Run in `example/` separately.',
        environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'});
  });
}
