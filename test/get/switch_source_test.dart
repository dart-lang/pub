// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  integration('re-gets a package if its source has changed', () {
    servePackages((builder) => builder.serve("foo", "1.2.3"));

    d.dir('foo',
        [d.libDir('foo', 'foo 0.0.1'), d.libPubspec('foo', '0.0.1')]).create();

    d.appDir({
      "foo": {"path": "../foo"}
    }).create();

    pubGet();

    d.appPackagesFile({"foo": "../foo"}).validate();
    d.appDir({"foo": "any"}).create();

    pubGet();

    d.appPackagesFile({"foo": "1.2.3"}).validate();
  });
}
