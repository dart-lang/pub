// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('warns if resolution is mixed mode', () async {
    await servePackages(
      (builder) => builder.serve(
        'foo',
        '1.2.3',
        pubspec: {
          'environment': {
            'sdk': '>=2.9.0 <3.0.0',
          }
        },
      ),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'my_app',
        'environment': {
          'sdk': '>=2.12.0 <3.0.0',
        },
        'dependencies': {'foo': 'any'}
      })
    ]).create();

    await pubGet(
        warning: contains(
            'Warning: The package resolution support only partial null-safety.\n\n'),
        environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
  });

  test('warns if resolution is mixed mode, single file opt out in dependency',
      () async {
    await servePackages(
      (builder) => builder.serve(
        'foo',
        '1.2.3',
        pubspec: {
          'environment': {
            'sdk': '>=2.12.0 <3.0.0',
          }
        },
        contents: [
          d.dir('lib', [d.file('foo.dart', '// @dart = 2.9')])
        ],
      ),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'my_app',
        'environment': {
          'sdk': '>=2.12.0 <3.0.0',
        },
        'dependencies': {'foo': 'any'}
      })
    ]).create();

    await pubGet(
        warning: contains(
            'The package resolution is not fully migrated to null-safety.\n\n'
            'package:foo/foo.dart is opting out of null safety:'),
        environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
  });

  test('warns if resolution is mixed mode, single file opt out in main package',
      () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'my_app',
        'environment': {
          'sdk': '>=2.12.0 <3.0.0',
        },
      }),
      d.dir('lib', [d.file('foo.dart', '// @dart = 2.9')])
    ]).create();

    await pubGet(
        warning: contains(
            'The package resolution is not fully migrated to null-safety.\n\n'
            'package:my_app/foo.dart is opting out of null safety:'),
        environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
  });

  test('No warning if main package is not opted in', () async {
    await servePackages(
      (builder) => builder.serve(
        'foo',
        '1.2.3',
        pubspec: {
          'environment': {
            'sdk': '>=2.12.0 <3.0.0',
          }
        },
        contents: [
          d.dir('lib', [d.file('foo.dart', '// @dart = 2.9')])
        ],
      ),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'my_app',
        'environment': {
          'sdk': '>=2.9.0 <3.0.0',
        },
        'dependencies': {'foo': 'any'}
      })
    ]).create();

    await pubGet(
        warning: isEmpty, environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'});
  });
}
