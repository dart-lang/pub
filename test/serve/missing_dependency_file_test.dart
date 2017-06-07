// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  test("responds with a 404 for a missing files in dependencies", () async {
    await d.dir("foo", [d.libPubspec("foo", "0.0.1")]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "foo": {"path": "../foo"}
      })
    ]).create();

    await pubGet();
    await pubServe();
    await requestShould404("packages/foo/nope.dart");
    await requestShould404("dir/packages/foo/nope.dart");
    await endPubServe();
  });
}
