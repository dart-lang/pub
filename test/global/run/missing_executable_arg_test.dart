// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../test_pub.dart';

main() {
  integration('fails if no executable was given', () {
    schedulePub(args: ["global", "run"],
        error: """
            Must specify an executable to run.

            Usage: pub global run <package>:<executable> [args...]
            -h, --help            Print this usage information.
            -c, --[no-]checked    Enable runtime type checks and assertions.
                --mode            Mode to run transformers in.
                                  (defaults to "release")

            Run "pub help" to see global options.
            """,
        exitCode: exit_codes.USAGE);
  });
}
