// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(
  error,
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
      'should consider a package valid if it contains no checked in otherwise ignored files',
      () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
      d.file('foo.txt'),
    ]).create();

    await expectValidation(contains('Package has 0 warnings.'), 0);

    await d.dir('myapp', [
      d.file('.gitignore', '*.txt'),
    ]).create();

    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains('foo.txt'),
        contains(
          'Consider adjusting your `.gitignore` files to not ignore those files',
        ),
      ]),
      exit_codes.DATA,
    );
  });

  test('should not fail on missing git', () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
      d.file('.gitignore', '*.txt'),
      d.file('foo.txt'),
    ]).create();

    await pubGet();
    await setUpFakeGitScript(bash: 'echo "Not git"', batch: 'echo "Not git"');
    await expectValidation(
      allOf([contains('Package has 0 warnings.')]),
      exit_codes.SUCCESS,
      environment: extendedPathEnv(),
    );
  });

  test('Should also consider gitignores from above the package root', () async {
    await d.git('reporoot', [
      d.dir(
        'myapp',
        [
          d.file('foo.txt'),
          ...d.validPackage().contents,
        ],
      ),
    ]).create();
    final packageRoot = p.join(d.sandbox, 'reporoot', 'myapp');
    await pubGet(workingDirectory: packageRoot);

    await expectValidation(
      contains('Package has 0 warnings.'),
      0,
      workingDirectory: packageRoot,
    );

    await d.dir('reporoot', [
      d.file('.gitignore', '*.txt'),
    ]).create();

    await expectValidation(
      allOf([
        contains('Package has 1 warning.'),
        contains('foo.txt'),
        contains(
          'Consider adjusting your `.gitignore` files to not ignore those files',
        ),
      ]),
      exit_codes.DATA,
      workingDirectory: packageRoot,
    );
  });

  test('Should not follow symlinks', () async {
    await d.git('myapp', [
      ...d.validPackage().contents,
    ]).create();
    final packageRoot = p.join(d.sandbox, 'myapp');
    await pubGet(workingDirectory: packageRoot);

    Link(p.join(packageRoot, '.abc', 'itself')).createSync(
      packageRoot,
      recursive: true,
    );

    await expectValidation(
      contains('Package has 0 warnings.'),
      0,
      workingDirectory: packageRoot,
    );
  });
}
