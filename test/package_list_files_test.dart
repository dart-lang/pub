// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/exceptions.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

late String root;
Entrypoint? entrypoint;

void main() {
  test('lists files recursively', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'}),
      d.file('file1.txt', 'contents'),
      d.file('file2.txt', 'contents'),
      d.dir('subdir', [
        d.file('subfile1.txt', 'subcontents'),
        d.file('subfile2.txt', 'subcontents'),
      ]),
      d.dir(Uri.encodeComponent('\\/%+-='), [
        d.file(Uri.encodeComponent('\\/%+-=')),
      ]),
    ]).create();
    createEntrypoint();

    expect(
      entrypoint!.workspaceRoot.listFiles(),
      unorderedEquals([
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file1.txt'),
        p.join(root, 'file2.txt'),
        p.join(root, 'subdir', 'subfile1.txt'),
        p.join(root, 'subdir', 'subfile2.txt'),
        p.join(
          root,
          Uri.encodeComponent('\\/%+-='),
          Uri.encodeComponent('\\/%+-='),
        ),
      ]),
    );
  });

  group('directory symlinks', () {
    test('not throws on valid directory symlinks', () async {
      await d.dir(appPath, [
        d.pubspec({'name': 'myapp'}),
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('subdir', [
          d.dir('a', [d.file('file')]),
          d.link('symlink', 'a', forceDirectory: true),
        ]),
      ]).create();

      createEntrypoint();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file1.txt'),
        p.join(root, 'file2.txt'),
        p.join(root, 'subdir', 'a', 'file'),
        p.join(root, 'subdir', 'symlink', 'file'),
      });
    });

    test('does not throw on ignored directory symlinks', () async {
      await d.dir(appPath, [
        d.pubspec({'name': 'myapp'}),
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('subdir', [
          d.file('.pubignore', 'symlink'),
          d.dir('a', [d.file('file')]),
          d.link('symlink', 'a', forceDirectory: true),
        ]),
      ]).create();

      createEntrypoint();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file1.txt'),
        p.join(root, 'file2.txt'),
        p.join(root, 'subdir', 'a', 'file'),
      });
    });

    test('does not throw on ignored broken directory symlinks', () async {
      await d.dir(appPath, [
        d.pubspec({'name': 'myapp'}),
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('subdir', [
          d.file('.pubignore', 'symlink'),
          d.dir('a', [d.file('file')]),
          d.link('symlink', 'b', forceDirectory: true),
        ]),
      ]).create();

      createEntrypoint();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file1.txt'),
        p.join(root, 'file2.txt'),
        p.join(root, 'subdir', 'a', 'file'),
      });
    });

    group('symlink cycles', () {
      test('throws on included link', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.dir('a', [d.file('file')]),
            d.link('symlink', '..', forceDirectory: true),
          ]),
        ]).create();

        createEntrypoint();

        expect(
          () => entrypoint!.workspaceRoot.listFiles(),
          throwsA(
            isA<DataException>().having(
              (e) => e.message,
              'message',
              contains('Pub does not support symlink cycles.'),
            ),
          ),
        );
      });

      test('throws on instant loop', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.dir('a', [d.file('file')]),
            d.link('symlink', 'symlink', forceDirectory: true),
          ]),
        ]).create();

        createEntrypoint();

        expect(
          () => entrypoint!.workspaceRoot.listFiles(),
          throwsA(
            isA<DataException>().having(
              (e) => e.message,
              'message',
              contains('Could not resolve symbolic link'),
            ),
          ),
        );
      });

      test('throws on nested loop', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.dir('a', [
              d.file('file'),
              d.link('symlink1', p.join('..', 'b'), forceDirectory: true),
            ]),
            d.dir('b', [
              d.link('symlink2', p.join('..', 'c'), forceDirectory: true),
            ]),
            d.dir('c', [
              d.link('symlink3', p.join('..', 'a'), forceDirectory: true),
            ]),
            d.link('symlink', 'a', forceDirectory: true),
          ]),
        ]).create();

        createEntrypoint();

        expect(
          () => entrypoint!.workspaceRoot.listFiles(),
          throwsA(
            isA<DataException>().having(
              (e) => e.message,
              'message',
              contains('Pub does not support symlink cycles.'),
            ),
          ),
        );
      });

      test('throws on link to loop', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.link('symlink', p.join(d.sandbox, 'loop'), forceDirectory: true),
        ]).create();
        await d.link('loop', 'loop', forceDirectory: true).create();

        createEntrypoint();

        expect(
          () => entrypoint!.workspaceRoot.listFiles(),
          throwsA(
            isA<DataException>().having(
              (e) => e.message,
              'message',
              contains('Could not resolve symbolic link'),
            ),
          ),
        );
      });

      test('throws on link to loop back to parent directory', () async {
        await d.dir('src', [
          d.dir(appPath, [
            d.pubspec({'name': 'myapp'}),
            d.link(
              'symlink',
              p.join(d.sandbox, 'source'),
              forceDirectory: true,
            ),
          ]),
        ]).create();
        await d
            .link('source', p.join(d.sandbox, 'src'), forceDirectory: true)
            .create();

        createEntrypoint(p.join('src', appPath));

        expect(
          () => entrypoint!.workspaceRoot.listFiles(),
          throwsA(
            isA<DataException>().having(
              (e) => e.message,
              'message',
              contains('Pub does not support symlink cycles.'),
            ),
          ),
        );
      });

      test(
        'throws on link to subdirectory of loop back to parent directory',
        () async {
          await d.dir('src', [
            d.dir(appPath, [
              d.pubspec({'name': 'myapp'}),
              d.link(
                'symlink',
                p.join(d.sandbox, 'source'),
                forceDirectory: true,
              ),
            ]),
          ]).create();
          await d
              .link('source', p.join(d.sandbox, 'src'), forceDirectory: true)
              .create();

          createEntrypoint(p.join('source', appPath));

          expect(
            () => entrypoint!.workspaceRoot.listFiles(),
            throwsA(
              isA<DataException>().having(
                (e) => e.message,
                'message',
                contains('Pub does not support symlink cycles.'),
              ),
            ),
          );
        },
      );

      test('Does not throw when publishing via symlink', () async {
        await d.dir('src', [
          d.dir(appPath, [
            d.pubspec({'name': 'myapp'}),
          ]),
        ]).create();
        await d
            .link('source', p.join(d.sandbox, 'src'), forceDirectory: true)
            .create();

        createEntrypoint(p.join('source', appPath));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
        });
      });

      test('not throws on ignored link', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.file('.pubignore', 'symlink'),
            d.dir('a', [d.file('file')]),
            d.link('symlink', '..', forceDirectory: true),
          ]),
        ]).create();

        createEntrypoint();

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'file1.txt'),
          p.join(root, 'file2.txt'),
          p.join(root, 'subdir', 'a', 'file'),
        });
      });

      test('not throws on valid links to the same directory', () async {
        await d.dir(appPath, [
          d.pubspec({'name': 'myapp'}),
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.dir('a', [d.file('file')]),
            d.link('symlink1', 'a', forceDirectory: true),
            d.link('symlink2', 'a', forceDirectory: true),
          ]),
          d.link('symlink3', p.join('subdir', 'a'), forceDirectory: true),
        ]).create();

        createEntrypoint();

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'file1.txt'),
          p.join(root, 'file2.txt'),
          p.join(root, 'subdir', 'a', 'file'),
          p.join(root, 'subdir', 'symlink1', 'file'),
          p.join(root, 'subdir', 'symlink2', 'file'),
          p.join(root, 'symlink3', 'file'),
        });
      });
    });
  });

  test('can list a package inside a symlinked folder', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'}),
      d.file('file1.txt', 'contents'),
      d.file('file2.txt', 'contents'),
      d.dir('subdir', [
        d.dir('a', [d.file('file')]),
      ]),
    ]).create();

    await d.link('symlink', appPath).create();
    root = p.join(d.sandbox, 'symlink');

    final entrypoint = Entrypoint(
      p.join(d.sandbox, 'symlink'),
      SystemCache(rootDir: p.join(d.sandbox, cachePath)),
    );

    expect(entrypoint.workspaceRoot.listFiles(), {
      p.join(root, 'pubspec.yaml'),
      p.join(root, 'file1.txt'),
      p.join(root, 'file2.txt'),
      p.join(root, 'subdir', 'a', 'file'),
    });
  });

  test('throws on non-resolving file symlinks', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'}),
      d.file('file1.txt', 'contents'),
      d.file('file2.txt', 'contents'),
      d.dir('subdir', [
        d.dir('a', [d.file('file')]),
        d.link('symlink', 'nonexisting'),
      ]),
    ]).create();

    createEntrypoint();

    expect(
      () => entrypoint!.workspaceRoot.listFiles(),
      throwsA(
        isA<DataException>().having(
          (e) => e.message,
          'message',
          contains('Could not resolve symbolic link'),
        ),
      ),
    );
  });

  test('throws on loop file symlinks', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'}),
      d.file('file1.txt', 'contents'),
      d.file('file2.txt', 'contents'),
      d.dir('subdir', [
        d.dir('a', [d.file('file')]),
      ]),
    ]).create();
    Link(p.join(d.sandbox, appPath, 'subdir', 'symlink')).createSync('symlink');

    createEntrypoint();

    expect(
      () => entrypoint!.workspaceRoot.listFiles(),
      throwsA(
        isA<DataException>().having(
          (e) => e.message,
          'message',
          contains('Could not resolve symbolic link'),
        ),
      ),
    );
  });

  test('throws on reciprocal symlinks', () async {
    await d.dir(appPath, [
      d.pubspec({'name': 'myapp'}),
      d.file('file1.txt', 'contents'),
      d.file('file2.txt', 'contents'),
      d.dir('subdir', [
        d.dir('a', [d.file('file')]),
      ]),
    ]).create();
    Link(
      p.join(d.sandbox, appPath, 'subdir', 'symlink1'),
    ).createSync('symlink2');
    Link(
      p.join(d.sandbox, appPath, 'subdir', 'symlink2'),
    ).createSync('symlink1');
    createEntrypoint();

    expect(
      () => entrypoint!.workspaceRoot.listFiles(),
      throwsA(
        isA<DataException>().having(
          (e) => e.message,
          'message',
          contains('Could not resolve symbolic link'),
        ),
      ),
    );
  });
  test('pubignore can undo the exclusion of .-files', () async {
    await d.dir(appPath, [
      d.file('.pubignore', '!.foo'),
      d.pubspec({'name': 'myapp'}),
      d.file('.foo', ''),
    ]).create();
    createEntrypoint();
    expect(entrypoint!.workspaceRoot.listFiles(), {
      p.join(root, '.foo'),
      p.join(root, 'pubspec.yaml'),
    });
  });
  group('with git', () {
    late d.GitRepoDescriptor repo;
    setUp(() async {
      ensureGit();
      repo = d.git(appPath, [d.appPubspec()]);
      await repo.create();
      createEntrypoint();
    });

    test("includes files that are or aren't checked in", () async {
      await d.dir(appPath, [
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('subdir', [
          d.file('subfile1.txt', 'subcontents'),
          d.file('subfile2.txt', 'subcontents'),
        ]),
      ]).create();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file1.txt'),
        p.join(root, 'file2.txt'),
        p.join(root, 'subdir', 'subfile1.txt'),
        p.join(root, 'subdir', 'subfile2.txt'),
      });
    });

    test('ignores files that are gitignored', () async {
      await d.dir(appPath, [
        d.file('.gitignore', '*.txt'),
        d.file('file1.txt', 'contents'),
        d.file('file2.text', 'contents'),
        d.dir('subdir', [
          d.file('subfile1.txt', 'subcontents'),
          d.file('subfile2.text', 'subcontents'),
        ]),
      ]).create();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file2.text'),
        p.join(root, 'subdir', 'subfile2.text'),
      });
    });

    test("ignores files that are gitignored even if the package isn't "
        'the repo root', () async {
      await d.dir(appPath, [
        d.file('.gitignore', '*.bak'),
        d.dir('rep', [
          d.file('.gitignore', '*.gak'),
          d.file('.pubignore', '*.hak'),
          d.dir('sub', [
            d.appPubspec(),
            d.file('.gitignore', '*.txt'),
            d.file('file1.txt', 'contents'),
            d.file('file2.text', 'contents'),
            d.file('file3.bak', 'contents'),
            d.file('file4.gak', 'contents'),
            d.file('file5.hak', 'contents'),
            d.dir('subdir', [
              d.file('subfile1.txt', 'subcontents'),
              d.file('subfile2.text', 'subcontents'),
            ]),
          ]),
        ]),
      ]).create();

      createEntrypoint(p.join(appPath, 'rep', 'sub'));

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'file2.text'),
        p.join(root, 'file4.gak'),
        p.join(root, 'subdir', 'subfile2.text'),
      });
    });

    group('with a submodule', () {
      setUp(() async {
        await d.git('submodule', [
          d.file('.gitignore', '*.txt'),
          d.file('file2.text', 'contents'),
        ]).create();

        await repo.runGit([
          // Hack to allow testing with local submodules after CVE-2022-39253.
          '-c',
          'protocol.file.allow=always',
          'submodule',
          'add',
          '../submodule',
        ]);

        await d.file('$appPath/submodule/file1.txt', 'contents').create();

        createEntrypoint();
      });

      test('respects its .gitignore with useGitIgnore', () {
        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'submodule', 'file2.text'),
        });
      });
    });

    test('ignores pubspec.lock files', () async {
      await d.dir(appPath, [
        d.file('pubspec.lock'),
        d.dir('subdir', [d.file('pubspec.lock')]),
      ]).create();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
      });
    });

    test('allows pubspec.lock directories', () async {
      await d.dir(appPath, [
        d.dir('pubspec.lock', [d.file('file.txt', 'contents')]),
      ]).create();

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'pubspec.lock', 'file.txt'),
      });
    });

    group('and "beneath"', () {
      test('only lists files beneath the given root', () async {
        await d.dir(appPath, [
          d.file('file1.txt', 'contents'),
          d.file('file2.txt', 'contents'),
          d.dir('subdir', [
            d.file('subfile1.txt', 'subcontents'),
            d.file('subfile2.txt', 'subcontents'),
            d.dir('subsubdir', [
              d.file('subsubfile1.txt', 'subsubcontents'),
              d.file('subsubfile2.txt', 'subsubcontents'),
            ]),
          ]),
        ]).create();

        expect(entrypoint!.workspaceRoot.listFiles(beneath: 'subdir'), {
          p.join(root, 'subdir', 'subfile1.txt'),
          p.join(root, 'subdir', 'subfile2.txt'),
          p.join(root, 'subdir', 'subsubdir', 'subsubfile1.txt'),
          p.join(root, 'subdir', 'subsubdir', 'subsubfile2.txt'),
        });
      });
    });

    test('.pubignore', () async {
      await d.validPackage().create();
      await d.dir(appPath, [
        d.file('.pubignore', '''
/lib/ignored.dart
'''),
        d.dir('lib', [d.file('ignored.dart', 'content')]),
        d.dir('lib', [d.file('not_ignored.dart', 'content')]),
      ]).create();
      createEntrypoint();
      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'LICENSE'),
        p.join(root, 'CHANGELOG.md'),
        p.join(root, 'README.md'),
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'lib', 'test_pkg.dart'),
        p.join(root, 'lib', 'not_ignored.dart'),
      });
    });
  });

  test('.pubignore overrides .gitignore', () async {
    ensureGit();
    final repo = d.git(appPath, [
      d.appPubspec(),
      d.file('.gitignore', '*.txt'),
      d.file('.pubignore', '*.text'),
      d.file('ignored_by_pubignore.text', ''),
      d.file('not_ignored_by_gitignore.txt', 'contents'),
      d.file('.hidden'),
      d.dir('gitignoredir', [
        d.file('.gitignore', 'foo'),
        d.file('foo'),
        d.file('bar'),
        d.file('a.txt'),
        d.file('a.text'),
        d.dir('nested', [
          d.file('.pubignore', '''
!foo
!*.text
'''),
          d.file('foo'),
          d.file('bar'),
          d.file('c.text'),
        ]),
      ]),
      d.dir('pubignoredir', [
        d.file('.pubignore', 'bar'),
        d.file('foo'),
        d.file('bar'),
        d.file('b.txt'),
        d.file('b.text'),
      ]),
    ]);
    await repo.create();
    createEntrypoint();
    await d.dir(appPath, [
      d.file('ignored_by_gitignore.txt', 'contents'),
      d.file('ignored_by_pubignore2.text', ''),
    ]).create();

    createEntrypoint();
    expect(entrypoint!.workspaceRoot.listFiles(), {
      p.join(root, 'pubspec.yaml'),
      p.join(root, 'not_ignored_by_gitignore.txt'),
      p.join(root, 'ignored_by_gitignore.txt'),
      p.join(root, 'gitignoredir', 'bar'),
      p.join(root, 'gitignoredir', 'a.txt'),
      p.join(root, 'gitignoredir', 'nested', 'foo'),
      p.join(root, 'gitignoredir', 'nested', 'bar'),
      p.join(root, 'gitignoredir', 'nested', 'c.text'),
      p.join(root, 'pubignoredir', 'foo'),
      p.join(root, 'pubignoredir', 'b.txt'),
    });
  });

  group('relative to current directory rules', () {
    setUp(ensureGit);
    group('delimiter in the beginning', () {
      test('ignore directory in exact directory', () async {
        final repo = d.git(appPath, [
          d.dir('packages', [
            d.dir('nested', [
              d.file('.gitignore', '/bin/'),
              d.appPubspec(),
              d.dir('bin', [d.file('run.dart')]),
            ]),
          ]),
        ]);
        await repo.create();
        createEntrypoint(p.join(appPath, 'packages', 'nested'));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
        });
      });

      test('ignore directory in exact directory', () async {
        final repo = d.git(appPath, [
          d.dir('packages', [
            d.dir('nested', [
              d.file('.gitignore', '/bin/'),
              d.appPubspec(),
              d.file('bin'),
            ]),
          ]),
        ]);
        await repo.create();
        createEntrypoint(p.join(appPath, 'packages', 'nested'));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'bin'),
        });
      });

      test('ignore file on exact directory', () async {
        final repo = d.git(appPath, [
          d.dir('packages', [
            d.dir('nested', [
              d.appPubspec(),
              d.dir('bin', [
                d.file('.gitignore', '/run.dart'),
                d.file('run.dart'),
              ]),
            ]),
          ]),
        ]);
        await repo.create();
        createEntrypoint(p.join(appPath, 'packages', 'nested'));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
        });
      });

      test('not ignore files beneath exact directory', () async {
        final repo = d.git(appPath, [
          d.dir('packages', [
            d.dir('nested', [
              d.appPubspec(),
              d.dir('bin', [
                d.file('.gitignore', '/run.dart'),
                d.file('run.dart'),
                d.dir('nested_again', [d.file('run.dart')]),
              ]),
            ]),
          ]),
        ]);
        await repo.create();
        createEntrypoint(p.join(appPath, 'packages', 'nested'));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'bin', 'nested_again', 'run.dart'),
        });
      });

      test('disable ignore in exact directory', () async {
        final repo = d.git(appPath, [
          d.dir('packages', [
            d.file('.gitignore', 'run.dart'),
            d.dir('nested', [
              d.appPubspec(),
              d.dir('bin', [
                d.file('.gitignore', '!/run.dart'),
                d.file('run.dart'),
                d.dir('nested_again', [d.file('run.dart')]),
              ]),
            ]),
          ]),
        ]);
        await repo.create();
        createEntrypoint(p.join(appPath, 'packages', 'nested'));

        expect(entrypoint!.workspaceRoot.listFiles(), {
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'bin', 'run.dart'),
        });
      });
    });
  });

  group('delimiter in the middle', () {
    test('should work with route relative to current directory ', () async {
      final repo = d.git(appPath, [
        d.dir('packages', [
          d.file('.gitignore', 'nested/bin/run.dart'),
          d.dir('nested', [
            d.appPubspec(),
            d.dir('bin', [
              d.file('run.dart'),
              d.dir('nested_again', [d.file('run.dart')]),
            ]),
          ]),
        ]),
      ]);
      await repo.create();
      createEntrypoint(p.join(appPath, 'packages', 'nested'));

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'bin', 'nested_again', 'run.dart'),
      });
    });

    test('should not have effect in nested folders', () async {
      final repo = d.git(appPath, [
        d.dir('packages', [
          d.file('.gitignore', 'bin/run.dart'),
          d.dir('nested', [
            d.appPubspec(),
            d.dir('bin', [
              d.file('run.dart'),
              d.dir('nested_again', [d.file('run.dart')]),
            ]),
          ]),
        ]),
      ]);
      await repo.create();
      createEntrypoint(p.join(appPath, 'packages', 'nested'));

      expect(entrypoint!.workspaceRoot.listFiles(), {
        p.join(root, 'pubspec.yaml'),
        p.join(root, 'bin', 'run.dart'),
        p.join(root, 'bin', 'nested_again', 'run.dart'),
      });
    });
  });
}

void createEntrypoint([String? path]) {
  path ??= appPath;
  root = p.join(d.sandbox, path);
  entrypoint = Entrypoint(root, SystemCache(rootDir: root));

  addTearDown(() {
    entrypoint = null;
  });
}
