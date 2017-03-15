// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  integration("responds with a 404 for missing assets", () {
    d.dir(appPath, [d.appPubspec()]).create();

    pubGet();
    pubServe();
    requestShould404("index.html");
    requestShould404("packages/myapp/nope.dart");
    requestShould404("dir/packages/myapp/nope.dart");
    endPubServe();
  });
}
