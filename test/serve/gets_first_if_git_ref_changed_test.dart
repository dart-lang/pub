// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test(
      "gets first if a git dependency's ref doesn't match the one in "
      "the lock file", () async {
    var repo = d.git(
        'foo.git', [d.libDir('foo', 'before'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();
    var commit1 = await repo.revParse('HEAD');

    await d.git('foo.git',
        [d.libDir('foo', 'after'), d.libPubspec('foo', '1.0.0')]).commit();

    var commit2 = await repo.revParse('HEAD');

    // Lock it to the ref of the first commit.
    await d.appDir({
      "foo": {
        "git": {"url": "../foo.git", "ref": commit1}
      }
    }).create();

    await pubGet();

    // Change the commit in the pubspec.
    await d.appDir({
      "foo": {
        "git": {"url": "../foo.git", "ref": commit2}
      }
    }).create();

    await pubGet();
    await pubServe();
    await requestShouldSucceed("packages/foo/foo.dart", 'main() => "after";');
    await endPubServe();
  });
}
