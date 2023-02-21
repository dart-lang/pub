// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('Gives nice error message when git ref is bad', () async {
    ensureGit();

    await d.git(
      'foo.git',
      [d.libDir('foo'), d.libPubspec('foo', '1.0.0')],
    ).create();

    await d.appDir(
      dependencies: {
        'foo': {
          'git': {'url': '../foo.git', 'ref': '^BAD_REF'}
        }
      },
    ).create();

    await pubGet(
      error:
          contains("Because myapp depends on foo from git which doesn't exist "
              "(Could not find git ref '^BAD_REF' (fatal: "),
      exitCode: UNAVAILABLE,
    );
  });
}
