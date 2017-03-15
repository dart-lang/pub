// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/sdk_constraint.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator sdkConstraint(Entrypoint entrypoint) =>
    new SdkConstraintValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    integration('has no SDK constraint', () {
      d.validPackage.create();
      expectNoValidationError(sdkConstraint);
    });

    integration('has an SDK constraint without ^', () {
      d.dir(appPath,
          [d.libPubspec("test_pkg", "1.0.0", sdk: ">=1.8.0 <2.0.0")]).create();
      expectNoValidationError(sdkConstraint);
    });

    integration(
        'has a Flutter SDK constraint with an appropriate Dart SDK '
        'constraint', () {
      d.dir(appPath, [
        d.pubspec({
          "name": "test_pkg",
          "version": "1.0.0",
          "environment": {"sdk": ">=1.19.0 <2.0.0", "flutter": "^1.2.3"}
        })
      ]).create();
      expectNoValidationError(sdkConstraint);
    });
  });

  group("should consider a package invalid if it", () {
    integration("has an SDK constraint with ^", () {
      d.dir(
          appPath, [d.libPubspec("test_pkg", "1.0.0", sdk: "^1.8.0")]).create();
      expect(
          schedulePackageValidation(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.8.0 <2.0.0"')), isEmpty)));
    });

    integration(
        "has a Flutter SDK constraint with a too-broad SDK "
        "constraint", () {
      d.dir(appPath, [
        d.pubspec({
          "name": "test_pkg",
          "version": "1.0.0",
          "environment": {"sdk": ">=1.18.0 <1.50.0", "flutter": "^1.2.3"}
        })
      ]).create();
      expect(
          schedulePackageValidation(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.19.0 <1.50.0"')), isEmpty)));
    });

    integration(
        "has a Flutter SDK constraint with no SDK "
        "constraint", () {
      d.dir(appPath, [
        d.pubspec({
          "name": "test_pkg",
          "version": "1.0.0",
          "environment": {"flutter": "^1.2.3"}
        })
      ]).create();
      expect(
          schedulePackageValidation(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.19.0 <2.0.0"')), isEmpty)));
    });
  });
}
