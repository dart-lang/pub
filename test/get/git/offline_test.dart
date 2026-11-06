// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    final warning =
        command == RunCommand.upgrade
            ? 'Warning: Upgrading when offline may not update you '
                'to the latest versions of your dependencies.'
            : null;

    test('uses the cached repository without fetching it', () async {
      ensureGit();

      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]).create();

      await d
          .appDir(
            dependencies: {
              'foo': {'git': '../foo.git'},
            },
          )
          .create();

      await pubGet();

      final originalFooSpec = packageSpec('foo');

      // Without a lock file, the versions of foo are listed again.
      deleteEntry(p.join(d.sandbox, appPath, 'pubspec.lock'));
      // Delete the repo, so that the command fails if it tries to fetch it.
      deleteEntry(p.join(d.sandbox, 'foo.git'));

      await pubCommand(command, args: ['--offline'], warning: warning);

      expect(packageSpec('foo'), originalFooSpec);
    });

    test('fails gracefully if the repository is not in cache', () async {
      ensureGit();

      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]).create();

      await d
          .appDir(
            dependencies: {
              'foo': {'git': '../foo.git'},
            },
          )
          .create();

      await pubCommand(
        command,
        args: ['--offline'],
        exitCode: exit_codes.UNAVAILABLE,
        error: allOf(
          contains('could not find git repository ../foo.git in cache'),
          contains('Try again without --offline!'),
        ),
      );
    });

    test(
      'fails gracefully if the ref is not in the cached repository',
      () async {
        ensureGit();

        final repo = d.git('foo.git', [
          d.libDir('foo'),
          d.libPubspec('foo', '1.0.0'),
        ]);
        await repo.create();

        await d
            .appDir(
              dependencies: {
                'foo': {'git': '../foo.git'},
              },
            )
            .create();

        await pubGet();

        // The cached clone of foo does not have this branch.
        await repo.runGit(['branch', 'new']);
        await d
            .appDir(
              dependencies: {
                'foo': {
                  'git': {'url': '../foo.git', 'ref': 'new'},
                },
              },
            )
            .create();

        await pubCommand(
          command,
          args: ['--offline'],
          exitCode: exit_codes.UNAVAILABLE,
          error: allOf(
            contains("Could not find git ref 'new'"),
            contains('Try again without --offline!'),
          ),
        );
      },
    );
  });

  test('get fails gracefully if the locked revision is not in cache', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();

    await pubGet();

    // Lock a revision that the first cache does not have: switch to a new
    // cache, commit to the repository and upgrade, then switch back.
    renameInSandbox(cachePath, '$cachePath.old');
    await d.git('foo.git', [
      d.libDir('foo', 'foo 2'),
      d.libPubspec('foo', '1.0.0'),
    ]).commit();
    await pubUpgrade(output: contains('Changed 1 dependency!'));
    final cacheDir = p.join(d.sandbox, cachePath);
    deleteEntry(cacheDir);
    renameInSandbox('$cachePath.old', cacheDir);

    // The repository is still there: only --offline keeps pub from fetching
    // the locked revision, so this fails instead of succeeding.
    await pubGet(
      args: ['--offline'],
      exitCode: exit_codes.UNAVAILABLE,
      error: allOf(
        contains('of ../foo.git is not available in cache'),
        contains('Try again without --offline!'),
      ),
    );
  });

  test(
    'get does not need the repository when the revision is checked out',
    () async {
      ensureGit();

      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]).create();

      await d
          .appDir(
            dependencies: {
              'foo': {'git': '../foo.git'},
            },
          )
          .create();

      await pubGet();

      final originalFooSpec = packageSpec('foo');

      // Keep the checkout of the locked revision, delete the cached repository.
      final repoCacheDir = p.join(d.sandbox, cachePath, 'git', 'cache');
      deleteEntry(repoCacheDir);
      deleteEntry(p.join(d.sandbox, packageConfigFilePath));

      await pubGet(args: ['--offline']);
      expect(packageSpec('foo'), originalFooSpec);

      deleteEntry(p.join(d.sandbox, packageConfigFilePath));
      await pubGet();
      expect(packageSpec('foo'), originalFooSpec);

      // The cached repository was not cloned again.
      expect(listDir(repoCacheDir), isEmpty);
    },
  );
}
