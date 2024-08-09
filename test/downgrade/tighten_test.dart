// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('--tighten will set lower bounds to the actually achieved version',
      () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
      ) // Because of the bar constraint, this is not achievable.
      ..serve('foo', '2.0.0')
      ..serve('foo', '3.0.0')
      ..serve('bar', '1.0.0', deps: {'foo': '>=2.0.0'});

    await d.appDir(dependencies: {'foo': '>=1.0.0', 'bar': '^1.0.0'}).create();

    await pubGet(output: contains('foo 3.0.0'));
    await pubDowngrade(
      args: ['--tighten'],
      output: allOf(
        contains('< foo 2.0.0 (was 3.0.0)'),
        contains('foo: >=1.0.0 -> >=2.0.0'),
      ),
    );
  });

  test('--tighten works for workspace with internal dependencies', () async {
    await servePackages();

    await d.dir(appPath, [
      d.libPubspec(
        'myapp',
        '1.2.3',
        extras: {
          'workspace': ['pkgs/a'],
        },
        sdk: '^3.5.0',
      ),
      d.dir('pkgs', [
        d.dir('a', [
          d.libPubspec(
            'a',
            '1.1.1',
            deps: {'myapp': '^1.0.0'},
            resolutionWorkspace: true,
          ),
        ]),
      ]),
    ]).create();

    await pubDowngrade(
      args: ['--tighten'],
      output: contains('myapp: ^1.0.0 -> ^1.2.3'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.5.0'},
    );
  });
}
