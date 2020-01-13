// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
      'Errors if the executable is in a subdirectory in a '
      'dependency.', () async {
    await d.dir('foo', [d.libPubspec('foo', '1.0.0')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await runPub(args: ['run', 'foo:sub/dir'], error: '''
Cannot run an executable in a subdirectory of a dependency.

Usage: pub run <executable> [args...]
-h, --help                   Print this usage information.
    --[no-]enable-asserts    Enable assert statements.

Run "pub help" to see global options.
See https://dart.dev/tools/pub/cmd/pub-run for detailed documentation.
''', exitCode: exit_codes.USAGE);
  });
}
