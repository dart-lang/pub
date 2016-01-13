// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  // Regression test for issue 22194.
  integration('gets a dependency with broken dev dependencies from a pub '
      'server', () {
    servePackages((builder) {
      builder.serve("foo", "1.2.3", pubspec: {
        "dev_dependencies": {
          "busted": {"not a real source": null}
        }
      });
    });

    d.appDir({"foo": "1.2.3"}).create();

    pubGet();

    d.cacheDir({"foo": "1.2.3"}).validate();
    d.packagesDir({"foo": "1.2.3"}).validate();
  });
}
