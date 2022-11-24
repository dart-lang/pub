// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Errors if the executable does not exist.', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await runPub(
      args: ['run'],
      error: contains('Must specify an executable to run.'),
      exitCode: exit_codes.USAGE,
    );
  });
}
