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
  // How pub prints the relative url `../foo.git` (`..\foo.git` on Windows).
  final prettyFooUrl = p.join('..', 'foo.git');

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

    test('checks out a revision from the cached repository', () async {
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

      // Keep the cached repository, delete the checkout of the revision.
      final gitCacheDir = p.join(d.sandbox, cachePath, 'git');
      final checkoutDirs = _revisionCheckoutDirs(gitCacheDir, 'foo');
      expect(checkoutDirs, hasLength(1));
      deleteEntry(checkoutDirs.single);
      // Delete the repo, so that the command fails if it tries to fetch it.
      deleteEntry(p.join(d.sandbox, 'foo.git'));

      await pubCommand(command, args: ['--offline'], warning: warning);

      expect(packageSpec('foo'), originalFooSpec);
      expect(_revisionCheckoutDirs(gitCacheDir, 'foo'), checkoutDirs);
    });

    test('checks out another ref of the cached repository', () async {
      ensureGit();

      final repo = d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]);
      await repo.create();
      // A branch on the first commit, the default branch on a second one.
      await repo.runGit(['branch', 'other']);
      await d.git('foo.git', [
        d.libDir('foo', 'foo 2'),
        d.libPubspec('foo', '1.0.0'),
      ]).commit();
      final otherCommit = await repo.revParse('other');

      await d
          .appDir(
            dependencies: {
              'foo': {'git': '../foo.git'},
            },
          )
          .create();

      // The cached repository gets the branch, not its checkout.
      await pubGet();
      expect(packageSpec('foo')['rootUri'], isNot(contains(otherCommit)));

      await d
          .appDir(
            dependencies: {
              'foo': {
                'git': {'url': '../foo.git', 'ref': 'other'},
              },
            },
          )
          .create();
      // Delete the repo, so that the command fails if it tries to fetch it.
      deleteEntry(p.join(d.sandbox, 'foo.git'));

      await pubCommand(command, args: ['--offline'], warning: warning);

      expect(packageSpec('foo')['rootUri'], contains(otherCommit));
    });

    test('resolves a tag_pattern dependency from the tags in cache', () async {
      ensureGit();

      final repo = d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]);
      await repo.create();
      await repo.tag('v1.0.0', tagType: d.TagType.annotated);

      await d
          .appDir(
            dependencies: {
              'foo': {
                'git': {'url': '../foo.git', 'tag_pattern': 'v{{version}}'},
                'version': '^1.0.0',
              },
            },
            pubspec: {
              'environment': {'sdk': '^3.9.0'},
            },
          )
          .create();

      await pubGet(
        output: contains('+ foo 1.0.0'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
      );

      // A new tag, not in the cached repository.
      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.5.0'),
      ]).commit();
      await repo.tag('v1.5.0', tagType: d.TagType.annotated);

      // Without a lock file, the versions of foo are listed again.
      deleteEntry(p.join(d.sandbox, appPath, 'pubspec.lock'));

      await pubCommand(
        command,
        args: ['--offline'],
        output: contains('+ foo 1.0.0'),
        warning: warning,
        environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
      );

      // Online, the new tag is found.
      await pubUpgrade(
        output: contains('> foo 1.5.0'),
        environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
      );
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
          contains('could not find git repository $prettyFooUrl in cache'),
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
        contains('of $prettyFooUrl is not available in cache'),
        contains('Try again without --offline!'),
      ),
    );
  });

  test(
    'get fails gracefully if the locked repository is not in cache',
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

      // Keep the lock file, empty the cache.
      deleteEntry(p.join(d.sandbox, cachePath));

      // The repository is still there: only --offline keeps pub from cloning
      // it, so this fails instead of succeeding.
      await pubGet(
        args: ['--offline'],
        exitCode: exit_codes.UNAVAILABLE,
        error: allOf(
          contains('could not find git repository $prettyFooUrl in cache'),
          contains('Try again without --offline!'),
        ),
      );
    },
  );

  test('get falls back to a cached tag when the locked tag_pattern revision '
      'is not in cache', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]);
    await repo.create();
    await repo.tag('v1.0.0', tagType: d.TagType.annotated);

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {'url': '../foo.git', 'tag_pattern': 'v{{version}}'},
              'version': '^1.0.0',
            },
          },
          pubspec: {
            'environment': {'sdk': '^3.9.0'},
          },
        )
        .create();

    await pubGet(
      output: contains('+ foo 1.0.0'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
    );

    // Lock a tagged revision that the first cache does not have: switch to a
    // new cache, tag a new version and upgrade, then switch back.
    renameInSandbox(cachePath, '$cachePath.old');
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.5.0'),
    ]).commit();
    await repo.tag('v1.5.0', tagType: d.TagType.annotated);
    await pubUpgrade(
      output: contains('> foo 1.5.0'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
    );
    final cacheDir = p.join(d.sandbox, cachePath);
    deleteEntry(cacheDir);
    renameInSandbox('$cachePath.old', cacheDir);

    // The locked version is not available offline, but the cached tags give
    // another version of foo matching the constraint.
    await pubGet(
      args: ['--offline'],
      output: contains('< foo 1.0.0'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.9.0'},
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

/// The revision checkouts of [packageName] in [gitCacheDir], such as
/// `PUB_CACHE/git/foo-<commit>`.
List<String> _revisionCheckoutDirs(String gitCacheDir, String packageName) => [
  for (final entry in listDir(gitCacheDir))
    if (p.basename(entry).startsWith('$packageName-')) entry,
]..sort();
