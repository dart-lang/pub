// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('checks out and upgrades a package from Git', () async {
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

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo'),
      ]),
    ]).validate();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo'),
      ]),
    ]).validate();

    final originalFooSpec = packageSpec('foo');

    await d.git('foo.git', [
      d.libDir('foo', 'foo 2'),
      d.libPubspec('foo', '1.0.0'),
    ]).commit();

    await pubUpgrade(output: contains('Changed 1 dependency!'));

    // When we download a new version of the git package, we should re-use the
    // git/cache directory but create a new git/ directory.
    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('foo', modifier: 2),
      ]),
    ]).validate();

    expect(packageSpec('foo'), isNot(originalFooSpec));
  });

  test('checks out and upgrades a package from with a tag-pattern', () async {
    ensureGit();

    final repo = d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]);
    await repo.create();
    await repo.tag('v1.0.0');

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {'url': '../foo.git', 'tag_pattern': 'v{{version}}'},
              'version': '^1.0.0',
            },
          },
          pubspec: {
            'environment': {'sdk': '^3.7.0'},
          },
        )
        .create();

    await pubGet(
      output: contains('+ foo 1.0.0'),
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
    );

    // This should be found by `pub upgrade`.
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.5.0'),
    ]).commit();
    await repo.tag('v1.5.0');

    // The untagged version should not be found by `pub upgrade`.
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.7.0'),
    ]).commit();

    // This should be found by `pub upgrade --major-versions`
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '2.0.0'),
    ]).commit();
    await repo.tag('v2.0.0');

    // A version that is not tagged according to the pattern should not be
    // chosen by the `upgrade --major-versions`.
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '3.0.0'),
    ]).commit();
    await repo.tag('unrelatedTag');

    await pubUpgrade(
      output: allOf(contains('> foo 1.5.0'), contains('Changed 1 dependency!')),
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
    );

    await pubUpgrade(
      args: ['--major-versions'],
      output: allOf(
        contains('> foo 2.0.0'),
        contains('foo: ^1.0.0 -> ^2.0.0'),
        contains('Changed 1 dependency!'),
      ),
      environment: {'_PUB_TEST_SDK_VERSION': '3.7.0'},
    );
  });
}
