// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('keeps a Git package locked to the version in the lockfile', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    // This get should lock the foo.git dependency to the current revision.
    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [
          d.gitPackageRepoCacheDir('foo'),
        ]),
        d.gitPackageRevisionCacheDir('foo'),
      ])
    ]).validate();

    var originalFooSpec = packageSpecLine('foo');

    // Delete the package spec to simulate a new checkout of the application.
    deleteEntry(path.join(d.sandbox, packagesFilePath));

    await d.git('foo.git',
        [d.libDir('foo', 'foo 2'), d.libPubspec('foo', '1.0.0')]).commit();

    // This get shouldn't upgrade the foo.git dependency due to the lockfile.
    await pubGet();

    expect(packageSpecLine('foo'), originalFooSpec);
  });
}
