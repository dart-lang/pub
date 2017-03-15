// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("does not compile if dart2js is disabled", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("main.dart", "void main() => print('hello');")])
    ]).create();

    pubGet();
    pubServe(args: ["--no-dart2js"]);
    requestShould404("main.dart.js");
    endPubServe();
  });
}
