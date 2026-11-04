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
          contains('could not find git repository'),
          contains('in cache'),
          contains('Try again without --offline!'),
        ),
      );
    });
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
    //
    // TODO: report 'is not available in cache' with the --offline hint. The
    // solver marks the locked version as invalid and the cached revision of
    // the ref has the same version, so the failure is reported as no
    // matching versions.
    await pubGet(
      args: ['--offline'],
      error: contains('version solving failed'),
    );
  });
}
