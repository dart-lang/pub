// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

void main() {
  test('fails if a version is passed with the path source', () {
    return runPub(
        args: ['global', 'activate', '-spath', 'foo', '1.2.3'],
        error: contains('Unexpected argument "1.2.3".'),
        exitCode: exit_codes.USAGE);
  });
}
