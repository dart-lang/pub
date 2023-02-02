// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('installs and activates the best version of a package', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi");')])
        ],
      )
      ..serve(
        'foo',
        '1.2.3',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi 1.2.3");')])
        ],
      )
      ..serve(
        'foo',
        '2.0.0-wildly.unstable',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi unstable");')])
        ],
      );

    await runPub(
      args: ['global', 'activate', 'foo'],
      output: '''
        Resolving dependencies...
        + foo 1.2.3
        Building package executables...
        Built foo:foo.
        Activated foo 1.2.3.''',
    );

    // Should be in global package cache.
    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo', [d.file('pubspec.lock', contains('1.2.3'))])
      ])
    ]).validate();
  });
}
