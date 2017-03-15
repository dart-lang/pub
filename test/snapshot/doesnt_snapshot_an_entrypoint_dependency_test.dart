// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration(
      "doesn't create a snapshot for a package that depends on the "
      "entrypoint", () {
    servePackages((builder) {
      builder.serve("foo", "1.2.3", deps: {
        'bar': '1.2.3'
      }, contents: [
        d.dir("bin", [d.file("hello.dart", "void main() => print('hello!');")])
      ]);
      builder.serve("bar", "1.2.3", deps: {'myapp': 'any'});
    });

    d.appDir({"foo": "1.2.3"}).create();

    pubGet();

    // No local cache should be created, since all dependencies transitively
    // depend on the entrypoint.
    d.nothing(p.join(appPath, '.pub', 'bin')).validate();
  });
}
