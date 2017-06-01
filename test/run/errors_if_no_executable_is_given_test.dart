// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test('Errors if the executable does not exist.', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await runPub(
        args: ["run"],
        error: """
Must specify an executable to run.

Usage: pub run <executable> [args...]
-h, --help            Print this usage information.
-c, --[no-]checked    Enable runtime type checks and assertions.
    --mode            Mode to run transformers in.
                      (defaults to "release" for dependencies, "debug" for entrypoint)

Run "pub help" to see global options.
""",
        exitCode: exit_codes.USAGE);
  });
}
