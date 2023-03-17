// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Future<void> setup({
  required String sdkConstraint,
  String? libraryLanguageVersion,
}) async {
  await d.validPackage().create();
  await d.dir(appPath, [
    d.validPubspec(
      extras: {
        'environment': {'sdk': sdkConstraint},
      },
    ),
    d.dir('lib', [
      if (libraryLanguageVersion != null)
        d.file('library.dart', '// @dart = $libraryLanguageVersion\n'),
    ])
  ]).create();
}

void main() {
  group('should consider a package valid if it', () {
    test('has no library-level language version annotations', () async {
      await setup(sdkConstraint: '^3.0.0');
      await expectValidation();
    });

    test('opts in to older language versions', () async {
      await setup(
        sdkConstraint: '^3.0.0',
        libraryLanguageVersion: '2.14',
      );
      await expectValidation();
    });
    test('opts in to same language versions', () async {
      await setup(
        sdkConstraint: '^3.0.0',
        libraryLanguageVersion: '3.0',
      );
      await expectValidation();
    });

    test('opts in to older language version, with non-range constraint',
        () async {
      await setup(sdkConstraint: '3.1.2+3', libraryLanguageVersion: '2.18');
      await expectValidation();
    });
  });

  group('should warn if it', () {
    test('opts in to a newer version.', () async {
      await setup(
        sdkConstraint: '^3.0.0',
        libraryLanguageVersion: '3.1',
      );
      await expectValidationWarning(
        'The language version override can\'t specify a version greater than the latest known language version',
      );
    });
    test('opts in to a newer version, with non-range constraint.', () async {
      await setup(sdkConstraint: '3.1.2+3', libraryLanguageVersion: '3.2');
      await expectValidationWarning(
        'The language version override can\'t specify a version greater than the latest known language version',
      );
    });
  });
}
