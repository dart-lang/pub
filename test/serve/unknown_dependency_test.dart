// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("responds with a 404 unknown dependencies", () {
    d.dir(appPath, [d.appPubspec()]).create();

    pubGet();
    pubServe();
    requestShould404("packages/foo/nope.dart");
    requestShould404("assets/foo/nope.png");
    requestShould404("dir/packages/foo/nope.dart");
    requestShould404("dir/assets/foo/nope.png");
    endPubServe();
  });
}
