// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('does not create binstubs if --no-executables is passed', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'one': null}
      }),
      d.dir('bin', [d.file('one.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    await runPub(args: [
      'global',
      'activate',
      '--source',
      'path',
      '../foo',
      '--no-executables'
    ]);

    // Should still delete old one.
    await d.dir(cachePath, [
      d.dir('bin', [d.nothing(binStubName('one'))])
    ]).validate();
  });
}
