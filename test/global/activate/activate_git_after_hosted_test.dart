// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activating a Git package deactivates the hosted one', () async {
    ensureGit();

    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      contents: [
        d.dir('bin', [d.file('foo.dart', "main(args) => print('hosted');")])
      ],
    );

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('git');")])
    ]).create();

    await runPub(args: ['global', 'activate', 'foo']);

    await runPub(
      args: ['global', 'activate', '-sgit', '../foo.git'],
      output: allOf(
        startsWith('Package foo is currently active at version 1.0.0.\n'
            'Resolving dependencies...\n'
            '* foo 1.0.0 from git ..${separator}foo.git at '),
        // Specific revision number goes here.
        endsWith('Building package executables...\n'
            'Built foo:foo.\n'
            'Activated foo 1.0.0 from Git repository "..${separator}foo.git".'),
      ),
    );

    // Should now run the git one.
    var pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emits('git'));
    await pub.shouldExit();
  });
}
