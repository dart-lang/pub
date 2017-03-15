// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("removes binstubs when the package is deactivated", () {
    servePackages((builder) {
      builder.serve("foo", "1.0.0", pubspec: {
        "executables": {"one": null, "two": null}
      }, contents: [
        d.dir("bin", [
          d.file("one.dart", "main(args) => print('one');"),
          d.file("two.dart", "main(args) => print('two');")
        ])
      ]);
    });

    schedulePub(args: ["global", "activate", "foo"]);
    schedulePub(args: ["global", "deactivate", "foo"]);

    d.dir(cachePath, [
      d.dir(
          "bin", [d.nothing(binStubName("one")), d.nothing(binStubName("two"))])
    ]).validate();
  });
}
