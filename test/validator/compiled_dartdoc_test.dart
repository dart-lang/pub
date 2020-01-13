// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/compiled_dartdoc.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator compiledDartdoc(Entrypoint entrypoint) =>
    CompiledDartdocValidator(entrypoint);

void main() {
  setUp(d.validPackage.create);

  group('should consider a package valid if it', () {
    test('looks normal', () => expectNoValidationError(compiledDartdoc));

    test('has most but not all files from compiling dartdoc', () async {
      await d.dir(appPath, [
        d.dir('doc-out', [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', '')
        ])
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });

    test('contains compiled dartdoc in a hidden directory', () async {
      ensureGit();

      await d.dir(appPath, [
        d.dir('.doc-out', [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ])
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });

    test('contains compiled dartdoc in a gitignored directory', () async {
      ensureGit();

      await d.git(appPath, [
        d.dir('doc-out', [
          d.file('nav.json', ''),
          d.file('index.html', ''),
          d.file('styles.css', ''),
          d.file('dart-logo-small.png', ''),
          d.file('client-live-nav.js', '')
        ]),
        d.file('.gitignore', '/doc-out')
      ]).create();
      expectNoValidationError(compiledDartdoc);
    });
  });

  group('should consider a package invalid if it', () {
    test('contains compiled dartdoc', () async {
      await d.dir(appPath, [
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

    test(
        'contains compiled dartdoc in a non-gitignored hidden '
        'directory', () async {
      ensureGit();

      await d.git(appPath, [
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
