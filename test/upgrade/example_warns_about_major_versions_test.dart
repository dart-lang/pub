// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.11

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

void main() {
  test(
      'pub upgrade --major-versions does not update major versions in example/',
      () async {
    await servePackages((b) => b
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
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
            'bar': 'any',
            'foo': '^1.0.0',
            'myapp': {'path': '..'}
          }
        })
      ])
    ]).create();

    final buffer = StringBuffer();
    await runPubIntoBuffer(
      ['upgrade', '--major-versions', '--example'],
      buffer,
    );
    await runPubIntoBuffer(
      ['upgrade', '--major-versions', '--directory', 'example'],
      buffer,
    );

    expectMatchesGoldenFile(
        buffer.toString(), 'test/goldens/upgrade_major_versions_example.txt');
  });

  test(
      'pub upgrade --null-safety does not update null-safety of dependencies in example/',
      () async {
    await servePackages((b) => b
      ..serve('foo', '1.0.0', pubspec: {
        'environment': {'sdk': '>=2.7.0 <3.0.0'},
      })
      ..serve('foo', '2.0.0', pubspec: {
        'environment': {'sdk': '>=2.12.0 <3.0.0'},
      })
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
        'environment': {'sdk': '>=2.12.0 <3.0.0'},
      }),
      d.dir('example', [
        d.pubspec({
          'name': 'app_example',
          'environment': {'sdk': '>=2.12.0 <3.0.0'},
          'dependencies': {
            'foo': '^1.0.0',
            // This will make the implicit upgrade of the example folder fail:
            'bar': '^1.0.0',
            'myapp': {'path': '..'}
          }
        })
      ])
    ]).create();

    final buffer = StringBuffer();
    await runPubIntoBuffer(
      ['upgrade', '--null-safety', '--example'],
      buffer,
      environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'},
    );

    await runPubIntoBuffer(
      ['upgrade', '--null-safety', '--directory', 'example'],
      buffer,
      environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'},
    );

    expectMatchesGoldenFile(
        buffer.toString(), 'test/goldens/upgrade_null_safety_example.txt');
  });
}
