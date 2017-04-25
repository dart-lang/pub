// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_stream.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  integration("compiler flag switches compilers", () {
    d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("hello.dart", "hello() => print('hello');"),
      ])
    ]).create();

    pubGet();
    var process = startPubServe(args: ['--compiler', 'dartdevc']);
    process.shouldExit(1);
    process.stderr
        .expect(consumeThrough('The dartdevc compiler is not yet supported.'));
  });
}
