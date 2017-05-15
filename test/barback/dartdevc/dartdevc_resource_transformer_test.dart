// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../descriptor.dart' as d;
import '../../test_pub.dart';
import '../../serve/utils.dart';

main() {
  integration("dartdevc resources are copied next to entrypoints", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("main.dart", 'void main() {}'),
      ]),
      d.dir("web", [
        d.file("main.dart", 'void main() {}'),
        d.dir("subdir", [
          d.file("main.dart", 'void main() {}'),
        ]),
      ]),
    ]).create();

    pubGet();
    pubServe(args: ['--compiler', 'dartdevc']);
    requestShouldSucceed('dart_sdk.js', null);
    requestShouldSucceed('require.js', null);
    requestShouldSucceed('subdir/dart_sdk.js', null);
    requestShouldSucceed('subdir/require.js', null);
    endPubServe();
  });
}
