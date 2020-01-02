// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/system_cache.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

String root;
Entrypoint entrypoint;

void main() {
  group('not in a git repo', () {
    setUp(() async {
      await d.appDir().create();
      createEntrypoint();
    });

    test('lists files recursively', () async {
      await d.dir(appPath, [
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('subdir', [
          d.file('subfile1.txt', 'subcontents'),
          d.file('subfile2.txt', 'subcontents')
        ])
      ]).create();

      expect(
          entrypoint.root.listFiles(),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, 'file1.txt'),
            p.join(root, 'file2.txt'),
            p.join(root, 'subdir', 'subfile1.txt'),
            p.join(root, 'subdir', 'subfile2.txt')
          ]));
    });

    commonTests();
  });

  group('with git', () {
    d.GitRepoDescriptor repo;
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
          d.file('subfile2.txt', 'subcontents')
        ])
      ]).create();

      expect(
          entrypoint.root.listFiles(),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, 'file1.txt'),
            p.join(root, 'file2.txt'),
            p.join(root, 'subdir', 'subfile1.txt'),
            p.join(root, 'subdir', 'subfile2.txt')
          ]));
    });

    test('ignores files that are gitignored if desired', () async {
      await d.dir(appPath, [
        d.file('.gitignore', '*.txt'),
        d.file('file1.txt', 'contents'),
        d.file('file2.text', 'contents'),
        d.dir('subdir', [
          d.file('subfile1.txt', 'subcontents'),
          d.file('subfile2.text', 'subcontents')
        ])
      ]).create();

      expect(
          entrypoint.root.listFiles(useGitIgnore: true),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, '.gitignore'),
            p.join(root, 'file2.text'),
            p.join(root, 'subdir', 'subfile2.text')
          ]));

      expect(
          entrypoint.root.listFiles(),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, 'file1.txt'),
            p.join(root, 'file2.text'),
            p.join(root, 'subdir', 'subfile1.txt'),
            p.join(root, 'subdir', 'subfile2.text')
          ]));
    });

    test(
        "ignores files that are gitignored even if the package isn't "
        'the repo root', () async {
      await d.dir(appPath, [
        d.dir('sub', [
          d.appPubspec(),
          d.file('.gitignore', '*.txt'),
          d.file('file1.txt', 'contents'),
          d.file('file2.text', 'contents'),
          d.dir('subdir', [
            d.file('subfile1.txt', 'subcontents'),
            d.file('subfile2.text', 'subcontents')
          ])
        ])
      ]).create();

      createEntrypoint(p.join(appPath, 'sub'));

      expect(
          entrypoint.root.listFiles(useGitIgnore: true),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, '.gitignore'),
            p.join(root, 'file2.text'),
            p.join(root, 'subdir', 'subfile2.text')
          ]));

      expect(
          entrypoint.root.listFiles(),
          unorderedEquals([
            p.join(root, 'pubspec.yaml'),
            p.join(root, 'file1.txt'),
            p.join(root, 'file2.text'),
            p.join(root, 'subdir', 'subfile1.txt'),
            p.join(root, 'subdir', 'subfile2.text')
          ]));
    });

    group('with a submodule', () {
      setUp(() async {
        await d.git('submodule', [
          d.file('.gitignore', '*.txt'),
          d.file('file2.text', 'contents')
        ]).create();

        await repo.runGit(['submodule', 'add', '../submodule']);

        await d.file('$appPath/submodule/file1.txt', 'contents').create();

        createEntrypoint();
      });

      test('ignores its .gitignore without useGitIgnore', () {
        expect(
            entrypoint.root.listFiles(),
            unorderedEquals([
              p.join(root, 'pubspec.yaml'),
              p.join(root, 'submodule', 'file1.txt'),
              p.join(root, 'submodule', 'file2.text'),
            ]));
      });

      test('respects its .gitignore with useGitIgnore', () {
        expect(
            entrypoint.root.listFiles(useGitIgnore: true),
            unorderedEquals([
              p.join(root, '.gitmodules'),
              p.join(root, 'pubspec.yaml'),
              p.join(root, 'submodule', '.gitignore'),
              p.join(root, 'submodule', 'file2.text'),
            ]));
      });
    });

    commonTests();
  });
}

void createEntrypoint([String path]) {
  path ??= appPath;
  root = p.join(d.sandbox, path);
  entrypoint = Entrypoint(root, SystemCache(rootDir: root));

  addTearDown(() {
    entrypoint = null;
  });
}

void commonTests() {
  test('ignores broken symlinks', () async {
    // Windows requires us to symlink to a directory that actually exists.
    await d.dir(appPath, [d.dir('target')]).create();
    symlinkInSandbox(p.join(appPath, 'target'), p.join(appPath, 'link'));
    deleteEntry(p.join(d.sandbox, appPath, 'target'));

    expect(entrypoint.root.listFiles(), equals([p.join(root, 'pubspec.yaml')]));
  });

  test('ignores pubspec.lock files', () async {
    await d.dir(appPath, [
      d.file('pubspec.lock'),
      d.dir('subdir', [d.file('pubspec.lock')])
    ]).create();

    expect(entrypoint.root.listFiles(), equals([p.join(root, 'pubspec.yaml')]));
  });

  test('ignores packages directories', () async {
    await d.dir(appPath, [
      d.dir('packages', [d.file('file.txt', 'contents')]),
      d.dir('subdir', [
        d.dir('packages', [d.file('subfile.txt', 'subcontents')]),
      ])
    ]).create();

    expect(entrypoint.root.listFiles(), equals([p.join(root, 'pubspec.yaml')]));
  });

  test('allows pubspec.lock directories', () async {
    await d.dir(appPath, [
      d.dir('pubspec.lock', [
        d.file('file.txt', 'contents'),
      ])
    ]).create();

    expect(
        entrypoint.root.listFiles(),
        unorderedEquals([
          p.join(root, 'pubspec.yaml'),
          p.join(root, 'pubspec.lock', 'file.txt')
        ]));
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
          ])
        ])
      ]).create();

      expect(
          entrypoint.root.listFiles(beneath: p.join(root, 'subdir')),
          unorderedEquals([
            p.join(root, 'subdir', 'subfile1.txt'),
            p.join(root, 'subdir', 'subfile2.txt'),
            p.join(root, 'subdir', 'subsubdir', 'subsubfile1.txt'),
            p.join(root, 'subdir', 'subsubdir', 'subsubfile2.txt')
          ]));
    });

    test("doesn't care if the root is blacklisted", () async {
      await d.dir(appPath, [
        d.file('file1.txt', 'contents'),
        d.file('file2.txt', 'contents'),
        d.dir('packages', [
          d.file('subfile1.txt', 'subcontents'),
          d.file('subfile2.txt', 'subcontents'),
          d.dir('subsubdir', [
            d.file('subsubfile1.txt', 'subsubcontents'),
            d.file('subsubfile2.txt', 'subsubcontents')
          ])
        ])
      ]).create();

      expect(
          entrypoint.root.listFiles(beneath: p.join(root, 'packages')),
          unorderedEquals([
            p.join(root, 'packages', 'subfile1.txt'),
            p.join(root, 'packages', 'subfile2.txt'),
            p.join(root, 'packages', 'subsubdir', 'subsubfile1.txt'),
            p.join(root, 'packages', 'subsubdir', 'subsubfile2.txt')
          ]));
    });
  });
}
