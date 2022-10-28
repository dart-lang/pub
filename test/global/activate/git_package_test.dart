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
                'Activated foo 1.0.0 from Git repository "..${p.separator}foo.git".')));
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
        '../foo.git',
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

  group('activates packages from Git repos with non-trivial refs', () {
    late String gitRepoPath;
    setUp(() async {
      // Generates a git repository with the following structure for the tests:
      //
      // * commit 25f3a8192e40ffcf2440008849560f3b90f75399 (a-branch)
      // | * commit cecd703af8cd1047f2631ca0bf677aad617bf50b (HEAD -> master)
      // | * commit ea74c8f2115b28b8fc4cb55926c564669c5d3489 (tag: a-tag)
      // |/
      // * commit 855ca7db03741823945496b6e656464736819dc8

      await d.git('foo.git', [
        d.libPubspec('foo', '0.0.0+initial'),
        d.dir(
            'bin', [d.file('foo.dart', "main() => print('hello from foo');")]),
        d.dir('sub', [
          d.libPubspec('sub', '0.0.0+initial'),
          d.dir('bin',
              [d.file('sub.dart', "main() => print('hello from sub');")]),
        ]),
      ]).create();

      var descriptor = d.git('foo.git', [
        d.libPubspec('foo', '0.0.0+a-branch'),
        d.dir('sub', [d.libPubspec('sub', '0.0.0+a-branch')])
      ]);
      await descriptor.runGit(['checkout', '-b', 'a-branch']);
      await descriptor.commit();

      await descriptor.runGit(['checkout', 'master']);
      descriptor = d.git('foo.git', [
        d.libPubspec('foo', '0.0.0+a-tag'),
        d.dir('sub', [d.libPubspec('sub', '0.0.0+a-tag')]),
      ]);
      await descriptor.commit();
      await descriptor.tag('a-tag');

      await d.git('foo.git', [
        d.libPubspec('foo', '0.0.0+master'),
        d.dir('sub', [d.libPubspec('sub', '0.0.0+master')]),
      ]).commit();

      // Using `file://<path>` is required to mimick a remote repository more closely
      // Otherwise, `git clone --depth 1` behaves differently: --depth is ignored in local clones; use file:// instead
      gitRepoPath = 'file://${descriptor.io.absolute.path}';
    });

    test('with branch name as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-path',
          'sub',
          '--git-ref',
          'a-branch',
        ],
        silent:
            contains('git checkout 25f3a8192e40ffcf2440008849560f3b90f75399'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'sub',
        ],
        output: contains('hello from sub'),
      );
    });

    test('with tag as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-path',
          'sub',
          '--git-ref',
          'a-tag',
        ],
        silent:
            contains('git checkout ea74c8f2115b28b8fc4cb55926c564669c5d3489'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'sub',
        ],
        output: contains('hello from sub'),
      );
    });

    test('with HEAD~ as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          'HEAD~',
        ],
        silent:
            contains('git checkout ea74c8f2115b28b8fc4cb55926c564669c5d3489'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'foo',
        ],
        output: contains('hello from foo'),
      );
    });

    test('with full commit SHA as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          '855ca7db03741823945496b6e656464736819dc8',
        ],
        silent:
            contains('git checkout 855ca7db03741823945496b6e656464736819dc8'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'foo',
        ],
        output: contains('hello from foo'),
      );
    });

    test('with partial commit SHA as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          '855ca7',
        ],
        silent:
            contains('git checkout 855ca7db03741823945496b6e656464736819dc8'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'foo',
        ],
        output: contains('hello from foo'),
      );
    });

    test('with HEAD~2 as --git-ref', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          'HEAD~2',
        ],
        silent:
            contains('git checkout 855ca7db03741823945496b6e656464736819dc8'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'foo',
        ],
        output: contains('hello from foo'),
      );
    });

    test('with master as --git-ref and activating it twice', () async {
      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          'master',
        ],
        silent:
            contains('git checkout cecd703af8cd1047f2631ca0bf677aad617bf50b'),
      );

      await runPub(
        args: [
          'global',
          'activate',
          '-s',
          'git',
          gitRepoPath,
          '--git-ref',
          'master',
        ],
        silent: contains('git show cecd703af8cd1047f2631ca0bf677aad617bf50b'),
      );

      await runPub(
        args: [
          'global',
          'run',
          'foo',
        ],
        output: contains('hello from foo'),
      );
    });
  });
}
