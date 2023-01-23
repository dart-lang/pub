// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('ignores previously activated version', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.2.3',
      )
      ..serve(
        'foo',
        '1.3.0',
        contents: [
          d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')])
        ],
      );

    // Activate 1.2.3.
    await runPub(args: ['global', 'activate', 'foo', '1.2.3']);

    // Activating it again resolves to the new best version.
    await runPub(
      args: ['global', 'activate', 'foo', '>1.0.0'],
      output: '''
        Package foo is currently active at version 1.2.3.
        Resolving dependencies...
        > foo 1.3.0 (was 1.2.3)
        Building package executables...
        Built foo:foo.
        Activated foo 1.3.0.''',
    );
  });
}
