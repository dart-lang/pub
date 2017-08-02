// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("cleans entire build directory before a build", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('example', [d.file('file.txt', 'example')]),
      d.dir('test', [d.file('file.txt', 'test')])
    ]).create();

    await pubGet();

    // Make a build directory containing "example".
    await runPub(
        args: ["build", "example"],
        output: new RegExp(r'Built 1 file to "build".'));

    // Now build again with just "test". Should wipe out "example".
    await runPub(
        args: ["build", "test"],
        output: new RegExp(r'Built 1 file to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.nothing('example'),
        d.dir('test', [d.file('file.txt', 'test')]),
      ])
    ]).validate();
  });
}
