// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('"--all" adds all non-installed versions of the package', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.1');
      builder.serve('foo', '1.2.2');
      builder.serve('foo', '1.2.3');
      builder.serve('foo', '2.0.0');
    });

    // Install a couple of versions first.
    await runPub(
        args: ['cache', 'add', 'foo', '-v', '1.2.1'],
        output: 'Downloading foo 1.2.1...');

    await runPub(
        args: ['cache', 'add', 'foo', '-v', '1.2.3'],
        output: 'Downloading foo 1.2.3...');

    // They should show up as already installed now.
    await runPub(args: ['cache', 'add', 'foo', '--all'], output: '''
          Already cached foo 1.2.1.
          Downloading foo 1.2.2...
          Already cached foo 1.2.3.
          Downloading foo 2.0.0...''');

    await d.cacheDir({'foo': '1.2.1'}).validate();
    await d.cacheDir({'foo': '1.2.2'}).validate();
    await d.cacheDir({'foo': '1.2.3'}).validate();
    await d.cacheDir({'foo': '2.0.0'}).validate();
  });
}
