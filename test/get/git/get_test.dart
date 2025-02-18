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

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]).create();

    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {'url': '../foo.git', 'ref': '^BAD_REF'},
            },
          },
        )
        .create();

    await pubGet(
      error: contains(
        "Because myapp depends on foo from git which doesn't exist "
        "(Could not find git ref '^BAD_REF' (fatal: ",
      ),
      exitCode: UNAVAILABLE,
    );
  });

  test('works with safe.bareRepository=explicit', () async {
    // https://git-scm.com/docs/git-config#Documentation/git-config.txt-safebareRepository
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]).create();
    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {'url': '../foo.git'},
            },
          },
        )
        .create();
    final gitConfigDir = d.dir('gitconfig');
    await gitConfigDir.create();
    await pubGet(
      environment: {
        // See https://git-scm.com/docs/git-config#ENVIRONMENT
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'safe.bareRepository',
        'GIT_CONFIG_VALUE_0': 'explicit',
      },
    );
    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '2.0.0'),
    ]).commit();

    await d
        .git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '2.0.0')])
        .runGit(['tag', '2.0.0']);
    await d
        .appDir(
          dependencies: {
            'foo': {
              'git': {'url': '../foo.git', 'ref': '2.0.0'},
            },
          },
        )
        .create();

    await pubGet(
      environment: {
        // See https://git-scm.com/docs/git-config#ENVIRONMENT
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'safe.bareRepository',
        'GIT_CONFIG_VALUE_0': 'explicit',
      },
      output: contains('2.0.0'),
    );
  });
}
