// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:path/path.dart' as p;

import '../io.dart';
import '../validator.dart';

//   If the `extension/devtools/` directory exists
//  verify the directory contains a file `config.yaml` and a non-empty `build/` directory
class DevtoolsExtensionValidator extends Validator {
  static String docUrl = 'https://docs.flutter.dev/tools/devtools/extensions';

  @override
  Future<void> validate() async {
    if (dirExists(p.join(package.dir, 'extension', 'devtools'))) {
      if (!files.any(
            (f) => p.equals(
              f,
              p.join(package.dir, 'extension', 'devtools', 'config.yaml'),
            ),
          ) ||
          !files.any(
            (f) => p.isWithin(
              p.join(package.dir, 'extension', 'devtools', 'build'),
              f,
            ),
          )) {
        warnings.add('''
It looks like you are making a devtools extension!

The folder `extension/devtools` should contain both a
* `config.yaml` file and a
* non-empty `build` directory'

See $docUrl.
''');
      }
    }
  }
}
