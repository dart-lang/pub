// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../test_pub.dart';

void expectNoValidationError(ValidatorCreator fn) {
  expect(validatePackage(fn), completion(pairOf(isEmpty, isEmpty)));
}

void expectValidationError(ValidatorCreator fn) {
  expect(validatePackage(fn), completion(pairOf(isNot(isEmpty), anything)));
}

void expectValidationWarning(ValidatorCreator fn) {
  expect(validatePackage(fn), completion(pairOf(isEmpty, isNot(isEmpty))));
}
