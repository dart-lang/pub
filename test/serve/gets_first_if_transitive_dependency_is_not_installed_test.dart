// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("gets first if a transitive dependency is not installed", () async {
    await servePackages((builder) => builder.serve("bar", "1.2.3"));

    await d.dir("foo", [
      d.libPubspec("foo", "1.0.0", deps: {"bar": "any"}),
      d.libDir("foo")
    ]).create();

    await d.appDir({
      "foo": {"path": "../foo"}
    }).create();

    // Run pub to install everything.
    await pubGet();

    // Delete the system cache so bar isn't installed any more.
    deleteEntry(path.join(d.sandbox, cachePath));

    await pubGet();
    await pubServe();
    await requestShouldSucceed(
        "packages/bar/bar.dart", 'main() => "bar 1.2.3";');
    await endPubServe();
  });
}
