// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("responds with a 404 on incomplete special URLs", () async {
    await d.dir("foo", [d.libPubspec("foo", "0.0.1")]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      }),
      d.dir("lib", [
        // Make a file that maps to the special "packages" directory to ensure
        // it is *not* found.
        d.file("packages")
      ]),
      d.dir("web", [d.file("packages")])
    ]).create();

    await pubGet();
    await pubServe();
    await requestShould404("packages");
    await requestShould404("packages/");
    await requestShould404("packages/myapp");
    await requestShould404("packages/myapp/");
    await requestShould404("packages/foo");
    await requestShould404("packages/foo/");
    await requestShould404("packages/unknown");
    await requestShould404("packages/unknown/");
    await endPubServe();
  });
}
