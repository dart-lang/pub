// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/pubspec_field.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator pubspecField(Entrypoint entrypoint) =>
    new PubspecFieldValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(pubspecField));

    test('has "authors" instead of "author"', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["authors"] = [pkg.remove("author")];
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectNoValidationError(pubspecField);
    });

    test('has an HTTPS homepage URL', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["homepage"] = "https://pub.dartlang.org";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectNoValidationError(pubspecField);
    });

    test('has an HTTPS documentation URL', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["documentation"] = "https://pub.dartlang.org";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectNoValidationError(pubspecField);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    test('is missing the "homepage" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg.remove("homepage");
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('is missing the "description" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg.remove("description");
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('is missing the "author" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg.remove("author");
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-string "homepage" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["homepage"] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-string "description" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["description"] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-string "author" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["author"] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-list "authors" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["authors"] = 12;
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-string member of the "authors" field', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["authors"] = [12];
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a single author without an email', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["author"] = "Natalie Weizenbaum";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationWarning(pubspecField);
    });

    test('has one of several authors without an email', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg.remove("author");
      pkg["authors"] = [
        "Bob Nystrom <rnystrom@google.com>",
        "Natalie Weizenbaum",
        "Jenny Messerly <jmesserly@google.com>"
      ];
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationWarning(pubspecField);
    });

    test('has a single author without a name', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["author"] = "<nweiz@google.com>";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationWarning(pubspecField);
    });

    test('has one of several authors without a name', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg.remove("author");
      pkg["authors"] = [
        "Bob Nystrom <rnystrom@google.com>",
        "<nweiz@google.com>",
        "Jenny Messerly <jmesserly@google.com>"
      ];
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationWarning(pubspecField);
    });

    test('has a non-HTTP homepage URL', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["homepage"] = "file:///foo/bar";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });

    test('has a non-HTTP documentation URL', () async {
      var pkg = packageMap("test_pkg", "1.0.0");
      pkg["documentation"] = "file:///foo/bar";
      await d.dir(appPath, [d.pubspec(pkg)]).create();

      expectValidationError(pubspecField);
    });
  });
}
