// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Pub must never run git through a shell. On Windows it used to spawn
/// `cmd /c git ...`, where `cmd.exe` treats `&` in an argument as a command
/// separator. These tests only fail on Windows if that regresses, but they
/// pass on all platforms.
@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

/// A relative file name, so the arguments below contain no whitespace
/// regardless of where the sandbox lives (`dart:io` quotes arguments
/// containing whitespace, which would neutralize `&` in `cmd.exe`).
const _proofFile = 'proof.txt';

/// Fails if a file named [_proofFile] exists anywhere in the sandbox.
void _expectNoProofFile() {
  expect(
    Directory(d.sandbox)
        .listSync(recursive: true)
        .map((entity) => entity.path)
        .where((path) => p.basename(path) == _proofFile),
    isEmpty,
  );
}

void main() {
  setUp(ensureGit);

  test(
    'passes a git ref containing shell metacharacters verbatim to git',
    () async {
      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]).create();

      const ref = 'HEAD&echo>$_proofFile';
      await d
          .appDir(
            dependencies: {
              'foo': {
                'git': {'url': '../foo.git', 'ref': ref},
              },
            },
          )
          .create();

      await pubGet(
        error: contains("Could not find git ref '$ref'"),
        exitCode: exit_codes.UNAVAILABLE,
      );
      _expectNoProofFile();
    },
  );

  test(
    'passes a git url containing shell metacharacters verbatim to git',
    () async {
      await d.git('foo.git', [
        d.libDir('foo'),
        d.libPubspec('foo', '1.0.0'),
      ]).create();

      // `../foo.git` exists, `../foo.git&echo` does not. If `&` were
      // interpreted by a shell, the clone of `../foo.git` would succeed.
      await d
          .appDir(
            dependencies: {
              'foo': {
                'git': {'url': '../foo.git&echo'},
              },
            },
          )
          .create();

      await pubGet(
        error: allOf(
          contains('foo.git&echo'),
          contains('does not appear to be a git repository'),
        ),
        exitCode: exit_codes.UNAVAILABLE,
      );
      _expectNoProofFile();
    },
  );

  test('ignores a git batch file on PATH', () async {
    // `cmd.exe` would prefer this `git.bat` over the real `git.exe` further
    // down PATH. Pub resolves `git` directly to a `git.exe`.
    await d.dir('bin', [
      d.file('git.bat', '@echo off\r\necho pwned>"%~dp0$_proofFile"\r\n'),
    ]).create();

    await d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0'),
    ]).create();
    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();

    await pubGet(
      environment: {
        'PATH': '${p.join(d.sandbox, 'bin')};${Platform.environment['PATH']}',
      },
    );

    expect(packageSpec('foo'), isNotNull);
    _expectNoProofFile();
  }, skip: Platform.isWindows ? false : 'Batch files only exist on Windows');

  test('explains an ignored git batch file when no git.exe is found', () async {
    await d.dir('bin', [d.file('git.bat', '@echo off\r\n')]).create();
    await d
        .appDir(
          dependencies: {
            'foo': {'git': '../foo.git'},
          },
        )
        .create();

    await pubGet(
      // Puts `bin/` first on PATH and removes directories containing a
      // `git.exe`.
      environment: extendedPathEnv(),
      error: allOf(
        contains('Cannot find a Git executable.'),
        contains(
          'Found "${p.join(d.sandbox, 'bin', 'git.bat')}", but only a '
          '`git.exe` can be used',
        ),
      ),
      exitCode: 1,
    );
  }, skip: Platform.isWindows ? false : 'Batch files only exist on Windows');
}
