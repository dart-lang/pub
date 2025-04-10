// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/sdk_constraint.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator sdkConstraint() => SdkConstraintValidator();

void main() {
  group('should consider a package valid if it', () {
    test('has no SDK constraint', () async {
      await d.validPackage().create();
      await expectValidationDeprecated(sdkConstraint);
    });

    test('has an SDK constraint without ^', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0 <2.0.0'),
      ]).create();
      await expectValidationDeprecated(sdkConstraint);
    });

    test('has an SDK constraint with ^', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', sdk: '^1.8.0'),
      ]).create();
      await expectValidationDeprecated(sdkConstraint);
    });

    test('depends on a pre-release Dart SDK from a pre-release', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0-dev.1', sdk: '>=1.8.0-dev.1 <2.0.0'),
      ]).create();
      await expectValidationDeprecated(sdkConstraint);
    });

    test('has a Flutter SDK constraint with an appropriate Dart SDK '
        'constraint', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'environment': {'sdk': '>=1.19.0 <2.0.0', 'flutter': '^1.2.3'},
        }),
      ]).create();
      await expectValidationDeprecated(sdkConstraint);
    });

    test('has a Fuchsia SDK constraint with an appropriate Dart SDK '
        'constraint', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'test_pkg',
          'version': '1.0.0-dev.1',
          'environment': {
            'sdk': '>=2.0.0-dev.51.0 <2.0.0',
            'fuchsia': '^1.2.3',
          },
        }),
      ]).create();
      await expectValidationDeprecated(sdkConstraint);
    });
  });

  group('should consider a package invalid if it', () {
    test('has no upper bound SDK constraint', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0'),
      ]).create();
      await expectValidationDeprecated(
        sdkConstraint,
        errors: anyElement(contains('should have an upper bound constraint')),
      );
    });

    test('has no SDK constraint', () async {
      await d.dir(appPath, [
        d.rawPubspec({'name': 'test_pkg', 'version': '1.0.0'}),
      ]).create();
      await expectValidationDeprecated(
        sdkConstraint,
        errors: anyElement(contains('should have an upper bound constraint')),
      );
    });

    test('depends on a pre-release sdk from a non-pre-release', () async {
      await d.dir(appPath, [
        d.libPubspec('test_pkg', '1.0.0', sdk: '>=1.8.0-dev.1 <2.0.0'),
      ]).create();
      await expectValidationDeprecated(
        sdkConstraint,
        warnings: anyElement(
          contains('consider publishing the package as a pre-release instead'),
        ),
      );
    });

    test('Gives a hint if package has a <3.0.0 constraint '
        'that is interpreted as <4.0.0', () async {
      await d.dir(appPath, [
        d.rawPubspec({
          'name': 'test_pkg',
          'version': '1.0.0',
          'environment': {'sdk': '^2.19.0'},
        }),
      ]).create();
      await expectValidationDeprecated(
        sdkConstraint,
        hints: anyElement('''
The declared SDK constraint is '^2.19.0', this is interpreted as '>=2.19.0 <4.0.0'.

Consider updating the SDK constraint to:

environment:
  sdk: '>=2.19.0 <4.0.0'
'''),
      );
    });
  });
}
