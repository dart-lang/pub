// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../golden_file.dart';
import '../test_pub.dart';

void main() {
  testWithGolden(
      'pub upgrade --major-versions does not update major versions in example/',
      (ctx) async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0');
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

    await ctx.run(['upgrade', '--major-versions', '--example']);
    await ctx.run(['upgrade', '--major-versions', '--directory', 'example']);
  });

  testWithGolden(
      'pub upgrade --null-safety does not update null-safety of dependencies in example/',
      (ctx) async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.7.0 <3.0.0'},
        },
      )
      ..serve(
        'foo',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.12.0 <3.0.0'},
        },
      )
      ..serve(
        'bar',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.7.0 <3.0.0'},
        },
      )
      ..serve(
        'bar',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '>=2.12.0 <3.0.0'},
        },
      );
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

    await ctx.run(
      ['upgrade', '--null-safety', '--example'],
      environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'},
    );

    await ctx.run(
      ['upgrade', '--null-safety', '--directory', 'example'],
      environment: {'_PUB_TEST_SDK_VERSION': '2.13.0'},
    );
  });
}
