// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

Future<void> expectValidation(error, int exitCode) async {
  await runPub(
    error: error,
    args: ['publish', '--dry-run'],
    environment: {
      'FLUTTER_ROOT': fakeFlutterRoot.io.path,
    },
    workingDirectory: d.path(appPath),
    exitCode: exitCode,
  );
}

late d.DirectoryDescriptor fakeFlutterRoot;

Future<void> setup({
  String? flutterConstraint,
}) async {
  fakeFlutterRoot = d.dir('fake_flutter_root', [d.file('version', '1.23.0')]);
  await fakeFlutterRoot.create();
  await d.validPackage().create();
  await d.dir(appPath, [
    d.pubspec({
      'name': 'test_pkg',
      'description':
          'A just long enough decription to fit the requirement of 60 characters',
      'homepage': 'https://example.com/',
      'version': '1.0.0',
      'environment': {
        'sdk': '^3.0.0',
        if (flutterConstraint != null) 'flutter': flutterConstraint
      },
    }),
  ]).create();
  await pubGet(
    environment: {'FLUTTER_ROOT': fakeFlutterRoot.io.path},
  );
}

void main() {
  test('No warning with no flutter constraint', () async {
    await setup();
    await expectValidation(contains('Package has 0 warnings.'), 0);
  });
  test('No warning with no flutter upper bound', () async {
    await setup(flutterConstraint: '>=1.20.0');
    await expectValidation(contains('Package has 0 warnings.'), 0);
  });
  test('Warn when upper bound', () async {
    await setup(flutterConstraint: '>=1.20.0 <=2.0.0');
    await expectValidation(
      allOf([
        contains(
          'You can replace that with just the lower bound: `>=1.20.0`.',
        ),
        contains('Package has 1 warning.'),
      ]),
      65,
    );
  });
  test('Warn when only upper bound', () async {
    await setup(flutterConstraint: '<2.0.0');
    await expectValidation(
      allOf([
        contains('You can replace the constraint with `any`.'),
        contains('Package has 1 warning.'),
      ]),
      65,
    );
  });
}
