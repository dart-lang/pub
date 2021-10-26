// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(
  error,
  int exitCode, {
  String workingDirectory,
}) async {
  await runPub(
    error: error,
    args: ['publish', '--dry-run'],
    environment: {'_PUB_TEST_SDK_VERSION': '2.12.0'},
    workingDirectory: workingDirectory ?? d.path(appPath),
    exitCode: exitCode,
  );
}

void main() {
  test(
      'should consider a package valid if it contains no checked in otherwise ignored files',
      () async {
    await d.git('myapp', [
      ...d.validPackage.contents,
      d.file('foo.txt'),
    ]).create();

    await pubGet(environment: {'_PUB_TEST_SDK_VERSION': '1.12.0'});

    await expectValidation(contains('Package has 0 warnings.'), 0);

    await d.dir('myapp', [
      d.file('.gitignore', '*.txt'),
    ]).create();

    await expectValidation(
        allOf([
          contains('Package has 1 warning.'),
          contains('foo.txt'),
          contains(
              'Consider adjusting your `.gitignore` files to not ignore those files'),
        ]),
        exit_codes.DATA);
  });

  test('Should also consider gitignores from above the package root', () async {
    await d.git('reporoot', [
      d.dir(
        'myapp',
        [
          d.file('foo.txt'),
          ...d.validPackage.contents,
        ],
      ),
    ]).create();
    final packageRoot = p.join(d.sandbox, 'reporoot', 'myapp');
    await pubGet(
        environment: {'_PUB_TEST_SDK_VERSION': '1.12.0'},
        workingDirectory: packageRoot);

    await expectValidation(contains('Package has 0 warnings.'), 0,
        workingDirectory: packageRoot);

    await d.dir('reporoot', [
      d.file('.gitignore', '*.txt'),
    ]).create();

    await expectValidation(
        allOf([
          contains('Package has 1 warning.'),
          contains('foo.txt'),
          contains(
              'Consider adjusting your `.gitignore` files to not ignore those files'),
        ]),
        exit_codes.DATA,
        workingDirectory: packageRoot);
  });
}
