// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  // Regression test for issue 20947.
  test(
      'checks out an unfetched and locked revision of a cached '
      'repository', () async {
    ensureGit();

    // In order to get a lockfile that refers to a newer revision than is in the
    // cache, we'll switch between two caches. First we ensure that the repo is
    // in the first cache.
    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    var originalFooSpec = packageSpecLine('foo');

    // Switch to a new cache.
    renameInSandbox(cachePath, '$cachePath.old');

    // Make the lockfile point to a new revision of the git repository.
    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    await pubUpgrade(output: contains('Changed 1 dependency!'));

    // Switch back to the old cache.
    var cacheDir = p.join(d.sandbox, cachePath);
    deleteEntry(cacheDir);
    renameInSandbox('$cachePath.old', cacheDir);

    // Get the updated version of the git dependency based on the lockfile.
    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo'),
        d.gitPackageRevisionCacheDir('foo', 2)
      ])
    ]).validate();

    expect(packageSpecLine('foo'), isNot(originalFooSpec));
  });
}
