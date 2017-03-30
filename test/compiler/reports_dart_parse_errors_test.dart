// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';
import 'package:scheduled_test/scheduled_stream.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  setUp(() {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [
        d.file('file.txt', 'contents'),
        d.file('file.dart', 'main() {}\nvoid void;'),
        d.dir('subdir', [d.file('subfile.dart', 'main() {}\nvoid void;')])
      ])
    ]).create();

    pubGet();
  });

  runTest("dart2js");
  runTest("dartdevc");
}

void runTest(String compiler) {
  group(compiler, () {
    integration("reports Dart parse errors", () {
      var pub = startPub(args: ["build", "--compiler", compiler]);
      pub.stdout.expect(startsWith("Loading source assets..."));
      pub.stdout.expect(startsWith("Building myapp..."));

      StreamMatcher consumeFile;
      StreamMatcher consumeSubfile;

      if (compiler == "dart2js") {
        consumeFile = consumeThrough(inOrder([
          startsWith("[Error from Dart2JS]:"),
          startsWith(p.join("web", "file.dart") + ":")
        ]));
        consumeSubfile = consumeThrough(inOrder([
          startsWith("[Error from Dart2JS]:"),
          startsWith(p.join("web", "subdir", "subfile.dart") + ":")
        ]));
      } else if (compiler == "dartdevc") {
        consumeFile = consumeThrough(inOrder([
          startsWith("[DevCompilerEntrypointModule]"),
          startsWith("Failed to compile package:myapp with dartdevc"),
          isEmpty,
          matches(new RegExp('\[error\].*\(web/file.dart, line 2, col 6\)')),
          matches(new RegExp('\[error\].*\(web/file.dart, line 2, col 10\)')),
          matches(new RegExp('\[error\].*\(web/file.dart, line 2, col 10\)')),
          isEmpty,
          "Please fix all errors before compiling (warnings are okay)."
        ]));
        consumeSubfile = consumeThrough(inOrder([
          startsWith("[DevCompilerEntrypointModule]"),
          startsWith("Failed to compile package:myapp with dartdevc"),
          isEmpty,
          matches(new RegExp(
              '\[error\].*\(web/subdir/subfile.dart, line 2, col 6\)')),
          matches(new RegExp(
              '\[error\].*\(web/subdir/subfile.dart, line 2, col 10\)')),
          matches(new RegExp(
              '\[error\].*\(web/subdir/subfile.dart, line 2, col 10\)')),
          isEmpty,
          "Please fix all errors before compiling (warnings are okay)."
        ]));
      } else {
        fail("Unsupported compiler `$compiler`");
      }

      // It's nondeterministic what order the dart2js transformers start running,
      // so we allow the error messages to be emitted in either order.
      pub.stderr.expect(either(inOrder([consumeFile, consumeSubfile]),
          inOrder([consumeSubfile, consumeFile])));

      pub.shouldExit(exit_codes.DATA);

      // Doesn't output anything if an error occurred.
      d.dir(appPath, [
        d.dir('build', [d.nothing('web')])
      ]).validate();
    });
  });
}
