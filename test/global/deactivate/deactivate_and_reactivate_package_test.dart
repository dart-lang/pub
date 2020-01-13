// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../test_pub.dart';

void main() {
  test('activates a different version after deactivating', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '2.0.0');
    });

    // Activate an old version.
    await runPub(args: ['global', 'activate', 'foo', '1.0.0']);

    await runPub(
        args: ['global', 'deactivate', 'foo'],
        output: 'Deactivated package foo 1.0.0.');

    // Activating again should forget the old version.
    await runPub(args: ['global', 'activate', 'foo'], output: '''
        Resolving dependencies...
        + foo 2.0.0
        Downloading foo 2.0.0...
        Precompiling executables...
        Activated foo 2.0.0.''');
  });
}
