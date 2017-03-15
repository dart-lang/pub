// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration(
      'Errors if the executable is in a subdirectory in a '
      'dependency.', () {
    d.dir("foo", [d.libPubspec("foo", "1.0.0")]).create();

    d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    schedulePub(
        args: ["run", "foo:sub/dir"],
        error: """
Cannot run an executable in a subdirectory of a dependency.

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
