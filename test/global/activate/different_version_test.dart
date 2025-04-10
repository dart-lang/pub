// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("discards the previous active version if it doesn't match the "
      'constraint', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi");')]),
        ],
      )
      ..serve(
        'foo',
        '2.0.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi2");')]),
        ],
      );

    // Activate 1.0.0.
    await runPub(args: ['global', 'activate', 'foo', '1.0.0']);

    // Activating it again with a different constraint changes the version.
    await runPub(
      args: ['global', 'activate', 'foo', '>1.0.0'],
      output: '''
        Package foo is currently active at version 1.0.0.
        Resolving dependencies...
        Downloading packages...
        > foo 2.0.0 (was 1.0.0)
        Building package executables...
        Built foo:foo.
        Activated foo 2.0.0.''',
    );
  });
}
