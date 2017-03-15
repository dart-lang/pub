// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration(
      "upgrades one locked pub server package's dependencies if it's "
      "necessary", () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", deps: {"foo_dep": "any"});
      builder.serve("foo_dep", "1.0.0");
    });

    d.appDir({"foo": "any"}).create();

    pubGet();

    d.appPackagesFile({"foo": "1.0.0", "foo_dep": "1.0.0"}).validate();

    globalPackageServer.add((builder) {
      builder.serve("foo", "2.0.0", deps: {"foo_dep": ">1.0.0"});
      builder.serve("foo_dep", "2.0.0");
    });

    pubUpgrade(args: ['foo']);

    d.appPackagesFile({"foo": "2.0.0", "foo_dep": "2.0.0"}).validate();
  });
}
