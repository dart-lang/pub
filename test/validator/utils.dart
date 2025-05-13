// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart';
import 'package:test/test.dart';

import '../test_pub.dart';

// TODO(sigurdm) consider rewriting all validator tests as integration tests.
// That would make them more robust, and test actual end2end behaviour.

// Prefer using expectValidation.
Future<void> expectValidationDeprecated(
  ValidatorCreator fn, {
  Object? hints,
  Object? warnings,
  Object? errors,
  int? size,
}) async {
  final validator = await validatePackage(fn, size);
  expect(validator.errors, errors ?? isEmpty);
  expect(validator.warnings, warnings ?? isEmpty);
  expect(validator.hints, hints ?? isEmpty);
}

Future<void> expectValidation({
  Object? message,
  int exitCode = 0,
  Map<String, String> environment = const {},
  List<String>? extraArgs,
  String? workingDirectory,
}) async {
  await runPub(
    output: message ?? contains('Package has 0 warnings.'),
    args: ['publish', '--dry-run', ...?extraArgs],
    // workingDirectory: d.path(appPath),
    exitCode: exitCode,
    environment: environment,
    workingDirectory: workingDirectory,
  );
}

Future<void> expectValidationWarning(
  String error, {
  int count = 1,
  Map<String, String> environment = const {},
}) async {
  final s = count == 1 ? '' : 's';
  await expectValidation(
    message: allOf([contains(error), contains('Package has $count warning$s')]),
    exitCode: DATA,
    environment: environment,
  );
}

Future<void> expectValidationHint(
  String hint, {
  int count = 1,
  Map<String, String> environment = const {},
  String? workingDirectory,
}) async {
  final s = count == 1 ? '' : 's';
  await expectValidation(
    message: allOf([contains(hint), contains('and $count hint$s')]),
    environment: environment,
    workingDirectory: workingDirectory,
  );
}

Future<void> expectValidationError(
  String text, {
  Map<String, String> environment = const {},
}) async {
  await expectValidation(
    message: allOf([
      contains(text),
      contains('Package validation found the following error:'),
    ]),
    exitCode: DATA,
    environment: environment,
  );
}
