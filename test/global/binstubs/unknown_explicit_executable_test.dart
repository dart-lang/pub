// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('errors on an unknown explicit executable', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'one': 'one'}
      }),
      d.dir('bin', [d.file('one.dart', "main() => print('ok');")])
    ]).create();

    var pub = await startPub(args: [
      'global', 'activate', '--source', 'path', '../foo', //
      '-x', 'who', '-x', 'one', '--executable', 'wat'
    ]);

    expect(pub.stdout, emitsThrough('Installed executable one.'));
    expect(pub.stderr, emits('Unknown executables wat and who.'));
    await pub.shouldExit(exit_codes.DATA);
  });
}
