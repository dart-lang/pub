// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

// Regression test for #1369.
main() {
  integration("gets and upgrades a package with a dev transformer", () {
    servePackages((builder) {
      builder.serveRealPackage('barback');

      builder.serve('foo', '1.0.0', pubspec: {
        'transformers': [
          {'bar': {r'$include': 'test/**'}}
        ],
        'dev_dependencies': {
          'bar': {'path': '../bar'}
        }
      });
    });

    d.appDir({'foo': '1.0.0'}).create();

    // Check for the error message because pub didn't consider this error fatal.
    pubGet(error: isEmpty, exitCode: 0);
  });
}
