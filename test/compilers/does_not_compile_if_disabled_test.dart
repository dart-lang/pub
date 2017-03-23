// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  group('--no-dart2js', () {
    runTest(['--no-dart2js']);
  });

  group('--compiler=none', () {
    runTest(['--compiler=none']);
  });
}

void runTest(List<String> pubArgs) {
  integration("does not compile if dart2js is disabled", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [d.file("main.dart", "void main() => print('hello');")])
    ]).create();

    pubGet();
    pubServe(args: pubArgs);
    requestShould404("main.dart.js");
    endPubServe();
  });
}
