// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

@TestOn('linux')
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' show sandbox;
import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart' show runProcess;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('reports failure if Git is not installed', () async {
    // Create temporary folder 'bin/' containing a 'git' script in [sandbox]
    // By adding the bin/ folder to the search `$PATH` we can prevent `pub` from
    // detecting the installed 'git' binary and we can test that it prints
    // a useful error message.
    await d.dir('bin', [
      d.file('git', '''
#!/bin/bash -e
echo "not git"
exit 1
'''),
    ]).create();
    final binFolder = p.join(sandbox, 'bin');
    // chmod the git script
    await runProcess('chmod', ['+x', p.join(sandbox, 'bin', 'git')]);

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet(
      environment: {
        // Override 'PATH' to ensure that we can't detect a working "git" binary
        'PATH': '$binFolder:${Platform.environment['PATH']}',
      },
      // We wish to verify that this error message is printed.
      error: contains('Cannot find a Git executable'),
      exitCode: 1, // exit code is non-zero.
    );
  });
}
