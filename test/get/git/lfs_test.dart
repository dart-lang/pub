// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('git dependencies with LFS', () async {
    final result = Process.runSync('git', ['lfs', 'version']);
    if (result.exitCode != 0) {
      fail('git-lfs not installed');
    }

    final repo = d.git('foo', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
      d.file('large.lfs', 'actual lfs content'),
    ]);
    await repo.create();

    // Initialize LFS in the remote repo.
    // --local Sets the "lfs" smudge and clean filters in the local repository's
    // git config, instead of the global git config (~/.gitconfig).
    await repo.runGit(['lfs', 'install', '--local']);
    await repo.runGit(['lfs', 'track', '*.lfs']);
    await repo.runGit(['add', '.gitattributes']);
    // We need to re-add the lfs file to make sure it's picked up by LFS.
    await repo.runGit(['add', 'large.lfs']);
    await repo.commit();

    // Verify it is an LFS file in the remote.
    final catResult = Process.runSync('git', [
      'cat-file',
      '-p',
      'HEAD:large.lfs',
    ], workingDirectory: p.join(d.sandbox, 'foo'));
    expect(
      catResult.stdout.toString(),
      contains('version https://git-lfs.github.com/spec/v1'),
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {
            'git': {'url': '../foo'},
          },
        },
      }),
    ]).create();

    await runPub(args: ['get']);

    final fooPathInCache = p.join(d.sandbox, cachePath, 'git');
    final revisionCacheDirs =
        Directory(fooPathInCache)
            .listSync()
            .whereType<Directory>()
            .where(
              (dir) =>
                  p.basename(dir.path).startsWith('foo-') &&
                  p.basename(p.dirname(dir.path)) == 'git',
            )
            .toList();

    expect(revisionCacheDirs, hasLength(1));
    final revisionCacheDir = revisionCacheDirs.first.path;

    // Verify lfsurl is set.
    final configResult = Process.runSync('git', [
      'config',
      'remote.origin.lfsurl',
    ], workingDirectory: revisionCacheDir);
    expect(configResult.stdout.toString().trim(), isNotEmpty);

    // Verify the file is smudged (contains actual content, not LFS pointer).
    final lfsFile = File(p.join(revisionCacheDir, 'large.lfs'));
    expect(lfsFile.readAsStringSync(), 'actual lfs content');

    // Test repair as well.
    lfsFile.writeAsStringSync('corrupted content');
    await runPub(args: ['cache', 'repair', '--all']);

    expect(lfsFile.readAsStringSync(), 'actual lfs content');
  });

  test(
    'regular git dependencies work even if git-lfs is "broken" or missing',
    () async {
      final repo = d.git('foo', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]);
      await repo.create();

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': {
              'git': {'url': '../foo'},
            },
          },
        }),
      ]).create();

      // Create a directory with a "broken" git-lfs to simulate it failing if
      // called.
      final fakeBinDir = p.join(d.sandbox, 'fake_bin');
      Directory(fakeBinDir).createSync();
      final fakeLfs = p.join(fakeBinDir, 'git-lfs');
      File(fakeLfs).writeAsStringSync('''
#!/bin/sh
echo "LFS called unexpectedly"
exit 1
''');
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', fakeLfs]);
      }

      final separator = Platform.isWindows ? ';' : ':';
      final newPath = '$fakeBinDir$separator${Platform.environment['PATH']}';

      // This should work because a regular repo doesn't trigger git-lfs.
      await runPub(args: ['get'], environment: {'PATH': newPath});

      await d.dir(appPath, [
        d.dir('.dart_tool', [d.file('package_config.json', contains('foo'))]),
      ]).validate();

      // Also verify that even if we set lfsurl, git doesn't care if lfs is
      // missing for a regular repo.
      final fooPathInCache = p.join(d.sandbox, cachePath, 'git');
      final revisionCacheDir =
          Directory(fooPathInCache)
              .listSync()
              .whereType<Directory>()
              .firstWhere((dir) => p.basename(dir.path).startsWith('foo-'))
              .path;

      final result = Process.runSync('git', [
        'config',
        'remote.origin.lfsurl',
      ], workingDirectory: revisionCacheDir);
      expect(result.stdout.toString().trim(), isNotEmpty);
    },
  );
}
