// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/deprecated_fields.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator deprecatedFields(Entrypoint entrypoint) =>
    DeprecatedFieldsValidator(entrypoint);

main() {
  setUp(d.validPackage.create);

  test('should not warn if neither transformers or web is included', () {
    expectNoValidationError(deprecatedFields);
  });

  test('should warn if pubspec has a transformers section', () async {
    await d.dir(appPath, [
      d.pubspec({
        'transformers': ['some_transformer']
      })
    ]).create();

    expectValidationWarning(deprecatedFields);
  });

  test('should warn if pubspec has a web section', () async {
    await d.dir(appPath, [
      d.pubspec({
        'web': {'compiler': 'dartdevc'}
      })
    ]).create();

    expectValidationWarning(deprecatedFields);
  });
}
