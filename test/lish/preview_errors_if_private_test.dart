// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('preview shows an error if the package is private', () {
    var pkg = packageMap("test_pkg", "1.0.0");
    pkg["publish_to"] = "none";
    d.dir(appPath, [d.pubspec(pkg)]).create();

    schedulePub(
        args: ["lish", "--dry-run"],
        error: startsWith("A private package cannot be published."),
        exitCode: exit_codes.DATA);
  });
}
