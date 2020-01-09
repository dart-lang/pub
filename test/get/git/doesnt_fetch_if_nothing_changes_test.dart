// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("doesn't re-fetch a repository if nothing changes", () async {
    ensureGit();

    await d.git(
        'foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]).create();

    await d.appDir({
      'foo': {
        'git': {'url': '../foo.git'}
      }
    }).create();

    await pubGet();

    var originalFooSpec = packageSpecLine('foo');

    // Delete the repo. This will cause "pub get" to fail if it tries to
    // re-fetch.
    deleteEntry(p.join(d.sandbox, 'foo.git'));

    await pubGet();

    expect(packageSpecLine('foo'), originalFooSpec);
  });
}
