// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart2js can take a long time to compile dart code, so we increase the timeout
// to cope with that.
@Timeout.factor(3)
import 'package:scheduled_test/scheduled_test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  integrationWithCompiler("converts a Dart isolate entrypoint in web to JS",
      (compiler) {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("web", [
        d.file(
            "isolate.dart",
            """
              import 'dart:isolate';
              void main(List<String> args, SendPort sendPort) => print('hello');
            """)
      ])
    ]).create();

    pubGet();
    pubServe(compiler: compiler);
    switch (compiler) {
      case Compiler.dart2JS:
        requestShouldSucceed("isolate.dart.js", contains("hello"));
        break;
      case Compiler.dartDevc:
        requestShouldSucceed("web__isolate.js", contains("hello"));
        break;
    }
    endPubServe();
  });
}
