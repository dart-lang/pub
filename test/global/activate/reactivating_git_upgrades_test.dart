// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('ignores previously activated git commit', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', 'main() => print("hi"); ')])
    ]).create();

    await runPub(
      args: ['global', 'activate', '-sgit', '../foo.git'],
      output: allOf(
        startsWith('Resolving dependencies...\n'
            '+ foo 1.0.0 from git ..${separator}foo.git at '),
        // Specific revision number goes here.
        endsWith('Building package executables...\n'
            'Built foo:foo.\n'
            'Activated foo 1.0.0 from Git repository "..${separator}foo.git".'),
      ),
    );

    await d.git('foo.git', [d.libPubspec('foo', '1.0.1')]).commit();

    // Activating it again pulls down the latest commit.
    await runPub(
      args: ['global', 'activate', '-sgit', '../foo.git'],
      output: allOf(
        startsWith('Package foo is currently active from Git repository '
            '"..${separator}foo.git".\n'
            'Resolving dependencies...\n'
            '> foo 1.0.1 from git ..${separator}foo.git at '),
        // Specific revision number goes here.
        endsWith('Building package executables...\n'
            'Built foo:foo.\n'
            'Activated foo 1.0.1 from Git repository "..${separator}foo.git".'),
      ),
    );
  });
}
