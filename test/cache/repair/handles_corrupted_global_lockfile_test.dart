// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('handles a corrupted global lockfile', () async {
    await d.dir(cachePath, [
      d.dir('global_packages/foo', [d.file('pubspec.lock', 'junk')])
    ]).create();

    await runPub(
        args: ['cache', 'repair'],
        error: contains('Failed to reactivate foo:'),
        output: contains('Failed to reactivate 1 package:\n'
            '- foo'),
        exitCode: exit_codes.UNAVAILABLE);
  });
}
