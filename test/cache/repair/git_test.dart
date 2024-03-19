// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  group('root-level packages', () {
    setUp(() async {
      // Create two cached revisions of foo.
      await d.git(
        'foo.git',
        [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
      ).create();

      await d.appDir(
        dependencies: {
          'foo': {'git': '../foo.git'},
        },
      ).create();
      await pubGet();

      await d.git(
        'foo.git',
        [d.libDir('foo'), d.libPubspec('foo', '1.0.1')],
      ).commit();

      await pubUpgrade();
    });

    test('reinstalls previously cached git packages', () async {
      // Find the cached foo packages for each revision.
      var gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      var fooDirs = listDir(gitCacheDir)
          .where((dir) => p.basename(dir).startsWith('foo-'))
          .toList();

      // Delete "foo.dart" from them.
      for (var dir in fooDirs) {
        deleteEntry(p.join(dir, 'lib', 'foo.dart'));
      }

      // Repair them.
      await runPub(
        args: ['cache', 'repair'],
        output: '''
          Resetting Git repository for foo 1.0.0...
          Resetting Git repository for foo 1.0.1...
          Reinstalled 2 packages.''',
      );

      // The missing libraries should have been replaced.
      var fooLibs = fooDirs.map((dir) {
        var fooDirName = p.basename(dir);
        return d.dir(fooDirName, [
          d.dir('lib', [d.file('foo.dart', 'main() => "foo";')]),
        ]);
      }).toList();

      await d.dir(cachePath, [d.dir('git', fooLibs)]).validate();
    });

    test('deletes packages without pubspecs', () async {
      var gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      var fooDirs = listDir(gitCacheDir)
          .where((dir) => p.basename(dir).startsWith('foo-'))
          .toList();

      for (var dir in fooDirs) {
        deleteEntry(p.join(dir, 'pubspec.yaml'));
      }

      await runPub(
        args: ['cache', 'repair'],
        error: allOf([
          contains('Failed to load package:'),
          contains('Could not find a file named "pubspec.yaml" in '),
          contains('foo-'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 2 packages:'),
          contains('- foo 0.0.0 from git'),
          contains('- foo 0.0.0 from git'),
        ]),
        exitCode: exit_codes.UNAVAILABLE,
      );

      await d.dir(cachePath, [
        d.dir('git', fooDirs.map((dir) => d.nothing(p.basename(dir)))),
      ]).validate();
    });

    test('deletes packages with invalid pubspecs', () async {
      var gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      var fooDirs = listDir(gitCacheDir)
          .where((dir) => p.basename(dir).startsWith('foo-'))
          .toList();

      for (var dir in fooDirs) {
        writeTextFile(p.join(dir, 'pubspec.yaml'), '{');
      }

      await runPub(
        args: ['cache', 'repair'],
        error: allOf([
          contains('Failed to load package:'),
          contains('Error on line 1, column 2 of '),
          contains('foo-'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 2 packages:'),
          contains('- foo 0.0.0 from git'),
          contains('- foo 0.0.0 from git'),
        ]),
        exitCode: exit_codes.UNAVAILABLE,
      );

      await d.dir(cachePath, [
        d.dir('git', fooDirs.map((dir) => d.nothing(p.basename(dir)))),
      ]).validate();
    });
  });

  group('subdirectory packages', () {
    setUp(() async {
      // Create two cached revisions of foo.
      await d.git('foo.git', [
        d.dir('subdir', [d.libDir('sub'), d.libPubspec('sub', '1.0.0')]),
      ]).create();

      await d.appDir(
        dependencies: {
          'sub': {
            'git': {'url': '../foo.git', 'path': 'subdir'},
          },
        },
      ).create();
      await pubGet();

      await d.git('foo.git', [
        d.dir('subdir', [d.libDir('sub'), d.libPubspec('sub', '1.0.1')]),
      ]).commit();

      await pubUpgrade();
    });

    test('reinstalls previously cached git packages', () async {
      // Find the cached foo packages for each revision.
      var gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      var fooDirs = listDir(gitCacheDir)
          .where((dir) => p.basename(dir).startsWith('foo-'))
          .toList();

      // Delete "sub.dart" from them.
      for (var dir in fooDirs) {
        deleteEntry(p.join(dir, 'subdir/lib/sub.dart'));
      }

      // Repair them.
      await runPub(
        args: ['cache', 'repair'],
        output: '''
          Resetting Git repository for sub 1.0.0...
          Resetting Git repository for sub 1.0.1...
          Reinstalled 2 packages.''',
      );

      // The missing libraries should have been replaced.
      var fooLibs = fooDirs.map((dir) {
        var fooDirName = p.basename(dir);
        return d.dir(fooDirName, [
          d.dir('subdir', [
            d.dir('lib', [d.file('sub.dart', 'main() => "sub";')]),
          ]),
        ]);
      }).toList();

      await d.dir(cachePath, [d.dir('git', fooLibs)]).validate();
    });

    test('deletes packages without pubspecs', () async {
      var gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      var fooDirs = listDir(gitCacheDir)
          .where((dir) => p.basename(dir).startsWith('foo-'))
          .toList();

      for (var dir in fooDirs) {
        deleteEntry(p.join(dir, 'subdir', 'pubspec.yaml'));
      }

      await runPub(
        args: ['cache', 'repair'],
        error: allOf([
          contains('Failed to load package:'),
          contains('Could not find a file named "pubspec.yaml" in '),
          contains('foo-'),
          contains('${p.separator}subdir'),
        ]),
        output: allOf([
          startsWith('Failed to reinstall 2 packages:'),
          contains('- foo 0.0.0 from git'),
          contains('- foo 0.0.0 from git'),
        ]),
        exitCode: exit_codes.UNAVAILABLE,
      );

      await d.dir(cachePath, [
        d.dir('git', fooDirs.map((dir) => d.nothing(p.basename(dir)))),
      ]).validate();
    });
  });
}
