// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  test('Gives hint when solve failure concerns a pinned flutter package',
      () async {
    await d.dir('flutter', [
      d.dir('packages', [
        d.dir(
          'flutter_foo',
          [
            d.libPubspec('flutter_foo', '0.0.1', deps: {'tool': '1.0.0'}),
          ],
        ),
      ]),
      d.file('version', '1.2.3'),
    ]).create();
    await servePackages()
      ..serve('bar', '1.0.0', deps: {'tool': '^2.0.0'})
      ..serve('tool', '1.0.0')
      ..serve('tool', '2.0.0');

    await d.appDir(
      dependencies: {
        'bar': 'any',
        'flutter_foo': {'sdk': 'flutter'},
      },
    ).create();
    await pubGet(
      environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
      error: contains(
        'Note: tool is pinned to version 1.0.0 by flutter_foo from the flutter SDK.',
      ),
    );
  });

  test('Gives hint when solve failure concerns a pinned flutter package',
      () async {
    await d.dir('flutter', [
      d.dir('packages', [
        d.dir(
          'flutter_foo',
          [
            d.libPubspec('flutter_foo', '0.0.1', deps: {'tool': '1.0.0'}),
          ],
        ),
      ]),
      d.file('version', '1.2.3'),
    ]).create();
    await servePackages()
      ..serve('tool', '1.0.0', deps: {'bar': '^2.0.0'})
      ..serve('bar', '1.0.0');

    await d.appDir(
      dependencies: {
        'bar': 'any',
        'flutter_foo': {'sdk': 'flutter'},
      },
    ).create();
    await pubGet(
      environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
      error: contains(
        'Note: tool is pinned to version 1.0.0 by flutter_foo from the flutter SDK.',
      ),
    );
  });
}
