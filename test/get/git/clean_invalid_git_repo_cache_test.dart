// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test('Clean-up invalid git repo cache', () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      "foo": {"git": "../foo.git"}
    }).create();

    await pubGet();

    await d.dir(cachePath, [
      d.dir('git', [
        d.dir('cache', [d.gitPackageRepoCacheDir('foo')]),
        d.gitPackageRevisionCacheDir('foo')
      ])
    ]).validate();

    final String cacheDir =
        path.join(d.sandbox, path.joinAll([cachePath, 'git', 'cache']));
    final Directory fooCacheDir =
        Directory(cacheDir).listSync().firstWhere((entity) {
      if (entity is Directory &&
          entity.path.split(Platform.pathSeparator).last.startsWith('foo'))
        return true;
    });
    fooCacheDir.deleteSync(recursive: true);
    fooCacheDir.createSync();

    await pubGet();
  });
}
