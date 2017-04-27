// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:scheduled_test/scheduled_test.dart';

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
    pubServe(args: ['--compiler', 'dartdevc']);
    requestShouldSucceed(
        'packages/$appPath/.moduleConfig', contains('lib__hello'));
    // Binary response, just confirm it exists.
    requestShouldSucceed('packages/$appPath/lib__hello.unlinked.sum', null);
    requestShouldSucceed('packages/$appPath/lib__hello.linked.sum', null);
    // TODO(jakemac53): Not implemented yet, update once available.
    requestShould404('packages/$appPath/lib__hello.js');
    endPubServe();
  });
}
