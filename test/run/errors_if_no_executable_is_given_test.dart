// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Errors if the executable does not exist.', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await runPub(args: ['run'], error: '''
Must specify an executable to run.

Usage: pub run <executable> [arguments...]
-h, --help                              Print this usage information.
    --[no-]enable-asserts               Enable assert statements.
    --enable-experiment=<experiment>    Runs the executable in a VM with the
                                        given experiments enabled.
                                        (Will disable snapshotting, resulting in
                                        slower startup).
    --[no-]sound-null-safety            Override the default null safety
                                        execution mode.

Run "pub help" to see global options.
See https://dart.dev/tools/pub/cmd/pub-run for detailed documentation.
''', exitCode: exit_codes.USAGE);
  });
}
