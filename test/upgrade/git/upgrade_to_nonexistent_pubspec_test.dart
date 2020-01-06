// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('upgrades Git packages to a nonexistent pubspec', () async {
    ensureGit();

    var repo =
        d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]);
    await repo.create();

    await d.appDir({
      'foo': {'git': '../foo.git'}
    }).create();

    await pubGet();

    var originalFooSpec = packageSpecLine('foo');

    await repo.runGit(['rm', 'pubspec.yaml']);
    await repo.runGit(['commit', '-m', 'delete']);

    await pubUpgrade(
        error: RegExp(r'Could not find a file named "pubspec.yaml" '
            r'in [^\n]*\.'));

    expect(packageSpecLine('foo'), originalFooSpec);
  });
}
