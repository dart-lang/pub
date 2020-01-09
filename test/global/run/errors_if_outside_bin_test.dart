// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('errors if the script is in a subdirectory.', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', contents: [
        d.dir('example', [d.file('script.dart', "main(args) => print('ok');")])
      ]);
    });

    await runPub(args: ['global', 'activate', 'foo']);
    await runPub(args: ['global', 'run', 'foo:example/script'], error: '''
Cannot run an executable in a subdirectory of a global package.

Usage: pub global run <package>:<executable> [args...]
-h, --help                   Print this usage information.
    --[no-]enable-asserts    Enable assert statements.

Run "pub help" to see global options.
''', exitCode: exit_codes.USAGE);
  });
}
