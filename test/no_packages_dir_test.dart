// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

main() {
  forBothPubGetAndUpgrade((command) {
    group("without --packages-dir", () {
      integration("removes package directories near entrypoints", () {
        d.dir(appPath, [
          d.appPubspec(),
          d.dir("packages"),
          d.dir("bin/packages"),
          d.dir("web/packages"),
          d.dir("web/subdir/packages")
        ]).create();

        pubCommand(command);

        d.dir(appPath, [
          d.nothing("packages"),
          d.nothing("bin/packages"),
          d.nothing("web/packages"),
          d.nothing("web/subdir/packages")
        ]).validate();
      });

      integration(
          "doesn't remove package directories that pub wouldn't "
          "generate", () {
        d.dir(appPath, [
          d.appPubspec(),
          d.dir("packages"),
          d.dir("bin/subdir/packages"),
          d.dir("lib/packages")
        ]).create();

        pubCommand(command);

        d.dir(appPath, [
          d.nothing("packages"),
          d.dir("bin/subdir/packages"),
          d.dir("lib/packages")
        ]).validate();
      });
    });
  });
}
