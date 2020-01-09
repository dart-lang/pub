// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('errors if -x and --no-executables are both passed', () async {
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

    await runPub(
        args: [
          'global',
          'activate',
          '--source',
          'path',
          '../foo',
          '-x',
          'anything',
          '--no-executables'
        ],
        error: contains('Cannot pass both --no-executables and --executable.'),
        exitCode: exit_codes.USAGE);
  });
}
