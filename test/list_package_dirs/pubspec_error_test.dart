// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:path/path.dart' as path;
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration("reports the pubspec path when there is an error in it", () {
    d.dir(appPath, [d.file("pubspec.yaml", "some bad yaml")]).create();

    schedulePub(args: [
      "list-package-dirs",
      "--format=json"
    ], outputJson: {
      "error": contains('Error on line 1'),
      "path": canonicalize(path.join(sandboxDir, appPath, "pubspec.yaml"))
    }, exitCode: exit_codes.DATA);
  });
}
