// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/pubspec_field.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator pubspecField() => PubspecFieldValidator();

void main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage().create);

    test('looks normal', () => expectValidationDeprecated(pubspecField));

    test('has an HTTPS homepage URL', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['homepage'] = 'https://pub.dev';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField);
    });

    test('has an HTTPS repository URL instead of homepage', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg.remove('homepage');
      pkg['repository'] = 'https://pub.dev';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField);
    });

    test('has an HTTPS documentation URL', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['documentation'] = 'https://pub.dev';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField);
    });

    test('has empty executables', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['executables'] = <String, String>{};
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField);
    });

    test('has executables', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['executables'] = <String, String?>{
        'test_pkg': null,
        'test_pkg_helper': 'helper',
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField);
    });
  });

  group('should warn if a package', () {
    test('is missing both the "homepage" and the "description" field',
        () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg.remove('homepage');
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, warnings: isNotEmpty);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage().create);

    test('is missing the "description" field', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg.remove('description');
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-string "homepage" field', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['homepage'] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-string "repository" field', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['repository'] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-string "description" field', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['description'] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-HTTP homepage URL', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['homepage'] = 'file:///foo/bar';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-HTTP documentation URL', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['documentation'] = 'file:///foo/bar';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has a non-HTTP repository URL', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['repository'] = 'file:///foo/bar';
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has invalid executables', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['executables'] = <String>['wrong-thing'];
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });

    test('has invalid executables mapping to a number', () async {
      var pkg = packageMap('test_pkg', '1.0.0');
      pkg['executables'] = <String, dynamic>{
        'test_pkg': 33,
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      await expectValidationDeprecated(pubspecField, errors: isNotEmpty);
    });
  });
}
