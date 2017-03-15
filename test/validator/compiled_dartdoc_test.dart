// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/compiled_dartdoc.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator compiledDartdoc(Entrypoint entrypoint) =>
    new CompiledDartdocValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    integration('looks normal', () => expectNoValidationError(compiledDartdoc));

    integration('has most but not all files from compiling dartdoc', () {
      d.dir(appPath, [
        d.dir("doc-out", [
          d.file("nav.json", ""),
          d.file("index.html", ""),
          d.file("styles.css", ""),
          d.file("dart-logo-small.png", "")
        ])
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });

    integration('contains compiled dartdoc in a hidden directory', () {
      ensureGit();

      d.dir(appPath, [
        d.dir(".doc-out", [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ])
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });

    integration('contains compiled dartdoc in a gitignored directory', () {
      ensureGit();

      d.git(appPath, [
        d.dir("doc-out", [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ]),
        d.file(".gitignore", "/doc-out")
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });
  });

  group("should consider a package invalid if it", () {
    integration('contains compiled dartdoc', () {
      d.validPackage.create();

      d.dir(appPath, [
        d.dir('doc-out', [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ])
      ]).create();

      expectValidationWarning(compiledDartdoc);
    });

    integration(
        'contains compiled dartdoc in a non-gitignored hidden '
        'directory', () {
      ensureGit();

      d.validPackage.create();

      d.git(appPath, [
        d.dir('.doc-out', [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ])
      ]).create();

      expectValidationWarning(compiledDartdoc);
    });
  });
}
