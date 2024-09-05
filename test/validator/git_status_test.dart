// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(
  Matcher error,
  int exitCode, {
  Map<String, String> environment = const {},
  String? workingDirectory,
}) async {
  await runPub(
    error: error,
    args: ['publish', '--dry-run'],
    environment: environment,
    workingDirectory: workingDirectory ?? d.path(appPath),
    exitCode: exitCode,
  );
}

void main() {
  test(
      'should consider a package valid '
      'if it contains no modified files (but contains a newly created one)',
      () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
      d.file('foo.txt', 'foo'),
      d.file('.pubignore', 'bob.txt\n'),
      d.file('bob.txt', 'bob'),
    ]).create();

    await d.dir('myapp', [
      d.file('bar.txt', 'bar'), // Create untracked file.
      d.file('bob.txt', 'bob2'), // Modify pub-ignored file.
    ]).create();

    await expectValidation(contains('Package has 0 warnings.'), 0);
  });

  test('Warns if files are modified', () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
      d.file('foo.txt', 'foo'),
    ]).create();

    await d.dir('myapp', [
      d.file('foo.txt', 'foo2'),
    ]).create();

    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains(
          '''
* 1 checked-in file is modified in git.
  
  Usually you want to publish from a clean git state.
  
  Consider committing these files or reverting the changes.
  
  Modified files:
  
  foo.txt
  
  Run `git status` for more information.''',
        ),
      ]),
      exit_codes.DATA,
    );

    // Stage but do not commit foo.txt. The warning should still be active.
    await d.git('myapp').runGit(['add', 'foo.txt']);
    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains('foo.txt'),
      ]),
      exit_codes.DATA,
    );
    await d.git('myapp').runGit(['commit', '-m', 'message']);

    await d.dir('myapp', [
      d.file('bar.txt', 'bar'), // Create untracked file.
      d.file('bob.txt', 'bob2'), // Modify pub-ignored file.
    ]).create();

    // Stage untracked file, now the warning should be about that.
    await d.git('myapp').runGit(['add', 'bar.txt']);

    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains(
          '''
* 1 checked-in file is modified in git.
  
  Usually you want to publish from a clean git state.
  
  Consider committing these files or reverting the changes.
  
  Modified files:
  
  bar.txt
  
  Run `git status` for more information.''',
        ),
      ]),
      exit_codes.DATA,
    );
  });

  test('Works with non-ascii unicode characters in file name', () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
      d.file('non_ascii_и.txt', 'foo'),
      d.file('non_ascii_и_ignored.txt', 'foo'),
      d.file('.pubignore', 'non_ascii_и_ignored.txt'),
    ]).create();
    await d.dir('myapp', [
      ...d.validPackage().contents,
      d.file('non_ascii_и.txt', 'foo2'),
      d.file('non_ascii_и_ignored.txt', 'foo2'),
    ]).create();

    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains(
          '''
* 1 checked-in file is modified in git.
  
  Usually you want to publish from a clean git state.
  
  Consider committing these files or reverting the changes.
  
  Modified files:
  
  non_ascii_и.txt
  
  Run `git status` for more information.''',
        ),
      ]),
      exit_codes.DATA,
    );
  });
}
