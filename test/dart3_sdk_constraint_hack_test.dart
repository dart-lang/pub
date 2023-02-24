// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  test('The bound of ">=2.11.0 <3.0.0" is not modified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.11.0 <3.0.0'}
      }),
    ]).create();

    await pubGet(
      error: contains(
        'The current version of the Dart SDK (3.5.0) does not support non-null\nsafety code.',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      exitCode: DATA,
    );
  });
  test('The bound of ">=2.12.0 <3.1.0" is not modified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.12.0 <3.1.0'}
      }),
    ]).create();

    await pubGet(
      error: contains(
        'Because myapp requires SDK version >=2.12.0 <3.1.0, version solving failed',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });

  test('The bound of ">=2.11.0 <2.999.0" is not modified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.11.0 <2.999.0'}
      }),
    ]).create();

    await pubGet(
      error: contains(
        'The current version of the Dart SDK (3.5.0) does not support non-null\nsafety code.',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      exitCode: DATA,
    );
  });

  test('The bound of ">=2.11.0 <3.0.0-0.0" is not modified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.11.0 <3.0.0-0.0'}
      }),
    ]).create();

    await pubGet(
      error: contains(
        'The current version of the Dart SDK (3.5.0) does not support non-null\nsafety code.',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      exitCode: DATA,
    );
  });

  test('The bound of ">=2.12.0 <3.0.0" is modified', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.12.0 <3.0.0'}
      }),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
  });

  test('The bound of ">=2.12.0 <3.0.0-0" is modified', () async {
    // For the upper bound <3.0.0 is treated as <3.0.0-0, so they both have
    // the rewrite applied.
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.12.0 <3.0.0-0'}
      }),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'});
  });

  test('The bound of ">=3.0.0-dev <3.0.0" is not modified', () async {
    // When the lower bound is a dev release of 3.0.0 the upper bound is treated literally, and not
    //  converted to 3.0.0-0, therefore the rewrite to 4.0.0 doesn't happen.
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=3.0.0-dev <3.0.0'}
      }),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
      error: contains(
        'Because myapp requires SDK version >=3.0.0-dev <3.0.0, version solving failed.',
      ),
    );
  });

  test(
      'The bound of ">=2.12.0 <3.0.0" is not compatible with prereleases of dart 4',
      () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.12.0 <3.0.0'}
      }),
    ]).create();

    await pubGet(
      environment: {'_PUB_TEST_SDK_VERSION': '4.0.0-alpha'},
      error: contains(
        'Because myapp requires SDK version >=2.12.0 <4.0.0, version solving failed.',
      ),
    );
  });

  test('When the constraint is not rewritten, a helpful hint is given',
      () async {
    await d.appDir(
      dependencies: {'foo': 'any'},
      pubspec: {
        'environment': {'sdk': '^2.12.0'}
      },
    ).create();
    final server = await servePackages();

    // foo is not null safe.
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '>=2.10.0 <3.0.0'}
      },
    );
    await pubGet(
      error: contains(
        'The lower bound of "sdk: \'>=2.10.0 <3.0.0\'" must be 2.12.0 or higher to enable null safety.'
        '\nFor details, see https://dart.dev/null-safety',
      ),
    );
  });

  test('Rewrite only happens after Dart 3', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '>=2.19.1 <3.0.0'}
      }),
    ]).create();

    await pubGet(
      error: contains(
        'Because myapp requires SDK version >=2.19.1 <3.0.0, version solving failed.',
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '2.19.0'},
    );
  });
}
