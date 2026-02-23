// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('dry-run with warnings exits with DATA error by default', () async {
    (await servePackages()).serve('foo', '1.0.0');
    await d
        .validPackage(
          pubspecExtras: {
            'dependencies': {'foo': 'any'},
          },
        )
        .create();

    await runPub(
      args: ['publish', '--dry-run'],
      output: contains('Package has 1 warning.'),
      exitCode: exit_codes.DATA,
    );
  });

  test(
    'dry-run with --ignore-warnings and warnings exits with SUCCESS',
    () async {
      (await servePackages()).serve('foo', '1.0.0');
      await d
          .validPackage(
            pubspecExtras: {
              'dependencies': {'foo': 'any'},
            },
          )
          .create();

      await runPub(
        args: ['publish', '--dry-run', '--ignore-warnings'],
        output: contains('Package has 1 warning.'),
        exitCode: exit_codes.SUCCESS,
      );
    },
  );

  test('--ignore-warnings without --dry-run is a usage error', () async {
    (await servePackages()).serve('foo', '1.0.0');
    await d
        .validPackage(
          pubspecExtras: {
            'dependencies': {'foo': 'any'},
          },
        )
        .create();

    await runPub(
      args: ['publish', '--ignore-warnings'],
      error: contains('`--ignore-warnings` can only be used with `--dry-run`.'),
      exitCode: exit_codes.USAGE,
    );
  });
}
