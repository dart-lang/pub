// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('allows internal relative symlinks in a git package', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('lib', [
        d.file('foo.dart', 'const foo = "foo";'),
        d.link('foo_link.dart', 'foo.dart'),
      ]),
      d.dir('ios', [d.file('classes.h', '// header')]),
      d.dir('macos', [d.link('classes.h', '../ios/classes.h')]),
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
        d.hashDir('foo', [
          d.libPubspec('foo', '1.0.0'),
          d.dir('lib', [
            d.file('foo.dart', 'const foo = "foo";'),
            d.link('foo_link.dart', 'foo.dart'),
          ]),
          d.dir('ios', [d.file('classes.h', '// header')]),
          d.dir('macos', [d.link('classes.h', '../ios/classes.h')]),
        ]),
      ]),
    ]).validate();

    expect(packageSpec('foo'), isNotNull);
  });

  test('rejects symlinks that escape repository via relative path', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('lib', [
        d.file('foo.dart', 'const foo = "foo";'),
        d.link('escape_link', '../../../../etc/passwd'),
      ]),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();

    await pubGet(
      error: contains(
        'contains a symbolic link "lib/escape_link" targeting "../../../../etc/passwd" which points outside the repository.',
      ),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });

  test('rejects absolute symlinks in a git package', () async {
    ensureGit();

    await d.git('foo.git', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('lib', [
        d.file('foo.dart', 'const foo = "foo";'),
        d.link('abs_link', '/etc/passwd'),
      ]),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();

    await pubGet(
      error: contains(
        'contains a symbolic link "lib/abs_link" targeting "/etc/passwd" which points outside the repository.',
      ),
      exitCode: exit_codes.UNAVAILABLE,
    );
  });
}
