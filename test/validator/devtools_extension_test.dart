// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

void main() {
  test('No warning if both are provided', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('extension', [
        d.dir('devtools', [
          d.file('config.yaml'),
          d.dir('build', [d.file('some_file')]),
        ]),
      ]),
    ]).create();
    await expectValidation();
  });
  test('warns if build-directory is empty', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('extension', [
        d.dir('devtools', [d.file('config.yaml'), d.dir('build', [])]),
      ]),
    ]).create();
    await expectValidationWarning(
      'The folder `extension/devtools` should contain both a',
    );
  });

  test('warns if config.yaml is missing', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.dir('extension', [
        d.dir('devtools', [
          d.dir('build', [d.file('some_file')]),
        ]),
      ]),
    ]).create();
    await expectValidationWarning(
      'The folder `extension/devtools` should contain both a',
    );
  });

  test('warns if config.yaml is ignored', () async {
    await d.validPackage().create();
    await d.dir(appPath, [
      d.file('.gitignore', 'extension/devtools/config.yaml'),
      d.dir('extension', [
        d.dir('devtools', [
          d.file('config.yaml'),
          d.dir('build', [d.file('some_file')]),
        ]),
      ]),
    ]).create();
    await expectValidationWarning(
      'The folder `extension/devtools` should contain both a',
    );
  });
}
