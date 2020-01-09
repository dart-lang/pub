// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

void main() {
  test('errors if the constraint matches no versions', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0');
      builder.serve('foo', '1.0.1');
    });

    await runPub(
        args: ['global', 'activate', 'foo', '>1.1.0'],
        error: equalsIgnoringWhitespace("""
          Because pub global activate depends on foo >1.1.0 which doesn't match
            any versions, version solving failed.
        """),
        exitCode: exit_codes.DATA);
  });
}
