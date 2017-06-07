// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/sdk_constraint.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator sdkConstraint(Entrypoint entrypoint) =>
    new SdkConstraintValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    test('has no SDK constraint', () async {
      await d.validPackage.create();
      expectNoValidationError(sdkConstraint);
    });

    test('has an SDK constraint without ^', () async {
      await d.dir(appPath,
          [d.libPubspec("test_pkg", "1.0.0", sdk: ">=1.8.0 <2.0.0")]).create();
      expectNoValidationError(sdkConstraint);
    });

    test(
        'has a Flutter SDK constraint with an appropriate Dart SDK '
        'constraint', () async {
      await d.dir(appPath, [
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
    test("has an SDK constraint with ^", () async {
      await d.dir(
          appPath, [d.libPubspec("test_pkg", "1.0.0", sdk: "^1.8.0")]).create();
      expect(
          validatePackage(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.8.0 <2.0.0"')), isEmpty)));
    });

    test(
        "has a Flutter SDK constraint with a too-broad SDK "
        "constraint", () async {
      await d.dir(appPath, [
        d.pubspec({
          "name": "test_pkg",
          "version": "1.0.0",
          "environment": {"sdk": ">=1.18.0 <1.50.0", "flutter": "^1.2.3"}
        })
      ]).create();
      expect(
          validatePackage(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.19.0 <1.50.0"')), isEmpty)));
    });

    test(
        "has a Flutter SDK constraint with no SDK "
        "constraint", () async {
      await d.dir(appPath, [
        d.pubspec({
          "name": "test_pkg",
          "version": "1.0.0",
          "environment": {"flutter": "^1.2.3"}
        })
      ]).create();
      expect(
          validatePackage(sdkConstraint),
          completion(
              pairOf(anyElement(contains('">=1.19.0 <2.0.0"')), isEmpty)));
    });
  });
}
