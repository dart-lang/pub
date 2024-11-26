// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../io.dart';
import '../validator.dart';

/// Validates that a package doesn't contain compiled Dartdoc output.
class CompiledDartdocValidator extends Validator {
  @override
  Future validate() {
    return Future.sync(() {
      for (var entry in files) {
        if (p.basename(entry) != 'nav.json') continue;
        final dir = p.dirname(entry);

        // Look for tell-tale Dartdoc output files all in the same directory.
        final files = [
          entry,
          p.join(dir, 'index.html'),
          p.join(dir, 'styles.css'),
          p.join(dir, 'dart-logo-small.png'),
          p.join(dir, 'client-live-nav.js'),
        ];

        if (files.every(fileExists)) {
          warnings.add('Avoid putting generated documentation in '
              '${p.relative(dir)}.\n'
              'Generated documentation bloats the package with redundant '
              'data.');
        }
      }
    });
  }
}
