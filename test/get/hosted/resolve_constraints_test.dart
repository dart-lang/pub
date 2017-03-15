// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration('resolves version constraints from a pub server', () {
    servePackages((builder) {
      builder.serve("foo", "1.2.3", deps: {"baz": ">=2.0.0"});
      builder.serve("bar", "2.3.4", deps: {"baz": "<3.0.0"});
      builder.serve("baz", "2.0.3");
      builder.serve("baz", "2.0.4");
      builder.serve("baz", "3.0.1");
    });

    d.appDir({"foo": "any", "bar": "any"}).create();

    pubGet();

    d.cacheDir({"foo": "1.2.3", "bar": "2.3.4", "baz": "2.0.4"}).validate();

    d.appPackagesFile(
        {"foo": "1.2.3", "bar": "2.3.4", "baz": "2.0.4"}).validate();
  });
}
