// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('fails gracefully if the package does not exist', () async {
      await serveNoPackages();

      await d.appDir({'foo': '1.2.3'}).create();

      await pubCommand(command,
          error: allOf([
            contains(
                "Because myapp depends on foo any which doesn't exist (could "
                'not find package foo at http://localhost:'),
            contains('), version solving failed.')
          ]),
          exitCode: exit_codes.UNAVAILABLE);
    });
  });
}
