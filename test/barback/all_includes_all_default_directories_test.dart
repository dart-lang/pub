// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../serve/utils.dart';
import '../test_pub.dart';

main() {
  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('benchmark', [d.file('file.txt', 'benchmark')]),
      d.dir('bin', [d.file('file.txt', 'bin')]),
      d.dir('example', [d.file('file.txt', 'example')]),
      d.dir('test', [d.file('file.txt', 'test')]),
      d.dir('web', [d.file('file.txt', 'web')]),
      d.dir('unknown', [d.file('file.txt', 'unknown')])
    ]).create();

    await pubGet();
  });

  test("build --all finds assets in default source directories", () async {
    await runPub(
        args: ["build", "--all"],
        output: new RegExp(r'Built 5 files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('benchmark', [d.file('file.txt', 'benchmark')]),
        d.dir('bin', [d.file('file.txt', 'bin')]),
        d.dir('example', [d.file('file.txt', 'example')]),
        d.dir('test', [d.file('file.txt', 'test')]),
        d.dir('web', [d.file('file.txt', 'web')]),
        // Only includes default source directories.
        d.nothing('unknown')
      ])
    ]).validate();
  });

  test("serve --all finds assets in default source directories", () async {
    await pubServe(args: ["--all"]);

    await requestShouldSucceed("file.txt", "benchmark", root: "benchmark");
    await requestShouldSucceed("file.txt", "bin", root: "bin");
    await requestShouldSucceed("file.txt", "example", root: "example");
    await requestShouldSucceed("file.txt", "test", root: "test");
    await requestShouldSucceed("file.txt", "web", root: "web");

    await expectNotServed("unknown");

    await endPubServe();
  });
}
