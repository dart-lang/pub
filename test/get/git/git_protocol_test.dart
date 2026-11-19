// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/git.dart' as git;
import 'package:pub/src/source/git.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('rejects git dependency with ext:: protocol in pubspec', () async {
    ensureGit();

    await git.run(['config', '--global', 'protocol.ext.allow', 'user']);
    addTearDown(() async {
      await git.run(['config', '--global', '--unset', 'protocol.ext.allow']);
    });

    final proofFile = p.join(d.sandbox, 'pwned.txt');

    await d
        .appDir(
          dependencies: {
            'foo': {'git': 'ext::sh -c touch\$IFS$proofFile @'},
          },
        )
        .create();

    await pubGet(
      error: contains('is not a valid Git URL'),
      exitCode: exit_codes.DATA,
    );

    expect(File(proofFile).existsSync(), isFalse);
  });

  test('rejects git dependency starting with a hyphen in pubspec', () async {
    await d
        .appDir(
          dependencies: {
            'foo': {'git': '--upload-pack=evil'},
          },
        )
        .create();

    await pubGet(
      error: contains('is not a valid Git URL'),
      exitCode: exit_codes.DATA,
    );
  });

  test('git clone passes -- to prevent option injection', () async {
    ensureGit();

    final tempDir = p.join(d.sandbox, 'temp_clone');

    // With '--', Git treats '--upload-pack=...' as a repository name rather
    // than a CLI option.
    expect(
      () => git.run([
        'clone',
        '--mirror',
        '--',
        '--upload-pack=touch /tmp/evil',
        tempDir,
      ]),
      throwsA(
        isA<git.GitException>().having(
          (e) => e.stderr,
          'stderr',
          isNot(contains('unknown option')),
        ),
      ),
    );
  });

  test('GitDescription validates URL schemes and syntax', () {
    expect(
      () => GitDescription(
        url: '-u/payload',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => GitDescription(
        url: 'ext::sh -c evil @',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => GitDescription(
        url: 'ext:///evil',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => GitDescription(
        url: 'https://example.com/@flutter/plugins.git',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      returnsNormally,
    );

    expect(
      () => GitDescription(
        url: 'ssh://git@example.com/flutter/plugins.git',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      returnsNormally,
    );

    expect(
      () => GitDescription(
        url: 'git@example.com:flutter/plugins.git',
        ref: 'main',
        path: '.',
        containingDir: null,
        tagPattern: null,
      ),
      returnsNormally,
    );
  });
}
