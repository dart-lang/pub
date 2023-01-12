// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activates a package from a Git repo', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    await runPub(
      args: ['global', 'activate', '-sgit', '../foo.git'],
      output: allOf(
        startsWith('Resolving dependencies...\n'
            '+ foo 1.0.0 from git ..${p.separator}foo.git at '),
        // Specific revision number goes here.
        endsWith('Building package executables...\n'
            'Built foo:foo.\n'
            'Activated foo 1.0.0 from Git repository "..${p.separator}foo.git".'),
      ),
    );
  });

  test('activates a package from a Git repo with path and ref', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '0.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('0');")]),
      d.dir(
        'sub',
        [
          d.libPubspec('foo', '1.0.0'),
          d.dir('bin', [d.file('sub.dart', "main() => print('1');")])
        ],
      ),
    ]).create();
    await d.git('foo.git', [
      d.dir(
        'sub',
        [
          d.libPubspec('sub', '2.0.0'),
          d.dir('bin', [d.file('sub.dart', "main() => print('2');")])
        ],
      ),
    ]).commit();
    await d.git('foo.git', [
      d.dir(
        'sub',
        [
          d.libPubspec('sub', '3.0.0'),
          d.dir('bin', [d.file('sub.dart', "main() => print('3');")])
        ],
      ),
    ]).commit();

    await runPub(
      args: [
        'global',
        'activate',
        '-sgit',
        // Testing with a file:// ur; is important here, as the cloning behavior
        // matches that of networked cloning. Specifically a shallow clone will
        // not be shallow if it is from a relative url.
        '${p.toUri(d.sandbox)}/foo.git',
        '--git-ref=HEAD~',
        '--git-path=sub/',
      ],
      output: allOf(
        startsWith('Resolving dependencies...\n'
            '+ sub 2.0.0 from git ..${p.separator}foo.git at'),
        // Specific revision number goes here.
        contains('in sub'),
        endsWith('Building package executables...\n'
            'Built sub:sub.\n'
            'Activated sub 2.0.0 from Git repository "..${p.separator}foo.git".'),
      ),
    );
    await runPub(
      args: [
        'global',
        'run',
        'sub',
      ],
      output: contains('2'),
    );
  });
}
