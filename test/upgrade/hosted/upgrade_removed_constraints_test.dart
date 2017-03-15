// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("upgrades dependencies whose constraints have been removed", () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", deps: {"shared_dep": "any"});
      builder.serve("bar", "1.0.0", deps: {"shared_dep": "<2.0.0"});
      builder.serve("shared_dep", "1.0.0");
      builder.serve("shared_dep", "2.0.0");
    });

    d.appDir({"foo": "any", "bar": "any"}).create();

    pubUpgrade();

    d.appPackagesFile(
        {"foo": "1.0.0", "bar": "1.0.0", "shared_dep": "1.0.0"}).validate();

    d.appDir({"foo": "any"}).create();

    pubUpgrade();

    d.appPackagesFile({"foo": "1.0.0", "shared_dep": "2.0.0"}).validate();
  });
}
