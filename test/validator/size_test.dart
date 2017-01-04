// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:pub/src/validator/size.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

ValidatorCreator size(int size) {
  return (entrypoint) =>
      new SizeValidator(entrypoint, new Future.value(size));
}

main() {
  setUp(d.validPackage.create);

  integration('considers a package valid if it is <= 100 MB', () {
    expectNoValidationError(size(100));
    expectNoValidationError(size(100 * math.pow(2, 20)));
  });

  integration('considers a package invalid if it is more than 100 MB', () {
    expectValidationError(size(100 * math.pow(2, 20) + 1));
  });
}
