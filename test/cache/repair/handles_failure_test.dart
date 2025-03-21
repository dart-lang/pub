// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('handles failure to reinstall some packages', () async {
    // Only serve two packages so repairing will have a failure.
    final server =
        await servePackages()
          ..serve('foo', '1.2.3')
          ..serve('foo', '1.2.5');

    // Set up a cache with some packages.
    await d.dir(cachePath, [
      d.dir('hosted', [
        d.dir('localhost%58${server.port}', [
          d.dir('foo-1.2.3', [
            d.libPubspec('foo', '1.2.3'),
            d.file('broken.txt'),
          ]),
          d.dir('foo-1.2.4', [
            d.libPubspec('foo', '1.2.4'),
            d.file('broken.txt'),
          ]),
          d.dir('foo-1.2.5', [
            d.libPubspec('foo', '1.2.5'),
            d.file('broken.txt'),
          ]),
        ]),
      ]),
    ]).create();

    // Repair them.
    final pub = await startPub(args: ['cache', 'repair']);

    expect(pub.stderr, emits(startsWith('Failed to repair foo 1.2.4. Error:')));
    expect(
      pub.stderr,
      emits(
        'Package not available '
        '(Package foo has no version 1.2.4).',
      ),
    );

    expect(pub.stdout, emits('Reinstalled 2 packages.'));
    expect(pub.stdout, emits('Failed to reinstall 1 package:'));
    expect(pub.stdout, emits('- foo 1.2.4'));

    await pub.shouldExit(exit_codes.UNAVAILABLE);
  });
}
