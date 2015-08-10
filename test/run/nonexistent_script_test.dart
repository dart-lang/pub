// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('Errors if the script does not exist.', () {
    d.dir(appPath, [
      d.appPubspec()
    ]).create();

    pubGet();
    var pub = pubRun(args: [p.join("bin", "script")]);
    pub.stderr.expect("Could not find ${p.join("bin", "script.dart")}.");
    pub.shouldExit(exit_codes.NO_INPUT);
  });
}
