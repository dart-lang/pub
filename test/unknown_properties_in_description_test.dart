// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('Ignores additional properties in descriptions before 3.7', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      sdk: '^3.6.0',
      deps: {
        'bar': {
          'hosted': {'url': server.url, 'unknown': 11},
        },
      },
    );
    server.serve('bar', '1.0.0');
    await d.appDir(
      pubspec: {
        'environment': {'sdk': '^3.6.0'},
      },
      dependencies: {
        'foo': {
          'hosted': {'url': server.url, 'unknown': 11},
          'version': '^1.0.0',
        },
      },
    ).create();
    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'});
  });

  test('Detects unknown attributes in descriptions in root project after 3.7',
      () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      sdk: '^3.6.0',
      deps: {
        'bar': {
          'hosted': {'url': server.url, 'unknown': 11},
        },
      },
    );
    server.serve('bar', '1.0.0');
    await d.appDir(
      pubspec: {
        'environment': {'sdk': '^3.7.0'},
      },
      dependencies: {
        'foo': {
          'hosted': {'url': server.url, 'unknown': 11},
          'version': '^1.0.0',
        },
      },
    ).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      error: contains('Invalid description in the "myapp" pubspec '
          'on the "foo" dependency: Unknown key "unknown" in description.'),
      exitCode: DATA,
    );
  });

  test('Detects unknown attributes in descriptions in dependency after 3.7',
      () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      sdk: '^3.7.0',
      deps: {
        'bar': {
          'hosted': {'url': server.url, 'unknown': 11},
        },
      },
    );
    server.serve('bar', '1.0.0');
    await d.appDir(
      pubspec: {
        'environment': {'sdk': '^3.6.0'},
      },
      dependencies: {
        'foo': {
          'hosted': {'url': server.url, 'unknown': 11},
          'version': '^1.0.0',
        },
      },
    ).create();
    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
      error: contains('Invalid description in the "foo" pubspec '
          'on the "bar" dependency: Unknown key "unknown" in description.'),
      exitCode: DATA,
    );
  });
}
