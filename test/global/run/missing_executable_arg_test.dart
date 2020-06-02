// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

void main() {
  test('fails if no executable was given', () {
    return runPub(args: ['global', 'run'], error: '''
Must specify an executable to run.

Usage: pub run <executable> [args...]
-h, --help                              Print this usage information.
    --[no-]enable-asserts               Enable assert statements.
    --enable-experiment=<experiment>    Runs the executable in a VM with the
                                        given experiments enabled. (Enabling
                                        experiments will disable source snapshot
                                        caching.)

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });
}
