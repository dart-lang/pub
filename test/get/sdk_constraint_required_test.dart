// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('pub get fails without an SDK constraint', () async {
    await d.dir(appPath, [
      d.rawPubspec({
        'name': 'myapp',
      }),
    ]).create();

    await pubGet(
      error: allOf(
        contains('pubspec.yaml has no lower-bound SDK constraint.'),
        contains("sdk: '^2.19.0'"),
      ),
      exitCode: exit_codes.DATA,
      environment: {'_PUB_TEST_SDK_VERSION': '2.19.1'},
    );

    await d.dir(appPath, [
      // The lockfile should not be created.
      d.nothing('pubspec.lock'),
      // The "packages" directory should not have been generated.
      d.nothing('packages'),
      // The package config file should not have been created.
      d.nothing('.dart_tool/package_config.json'),
    ]).validate();
  });

  test('pub get fails with an non-null-safety SDK constraint', () async {
    await d.dir(appPath, [
      d.rawPubspec(
        {
          'name': 'myapp',
          'environment': {'sdk': '>=2.9.0 <4.0.0'}
        },
      ),
    ]).create();

    await pubGet(
      error: '''
The lower bound of "sdk: '>=2.9.0 <4.0.0'" must be 2.12.0'
or higher to enable null safety.

The current version of the Dart SDK (3.1.2+3) does not support non-null
safety code.

Consider using an older, compatible Dart SDK or try the following sdk
constraint:

environment:
  sdk: '^3.1.0'

For details, see https://dart.dev/null-safety
''',
      exitCode: exit_codes.DATA,
    );

    await d.dir(appPath, [
      // The lockfile should not be created.
      d.nothing('pubspec.lock'),
      // The "packages" directory should not have been generated.
      d.nothing('packages'),
      // The package config file should not have been created.
      d.nothing('.dart_tool/package_config.json'),
    ]).validate();
  });
}
