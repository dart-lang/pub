// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';

main() {
  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bar', [d.file('file.txt', 'bar')]),
      d.dir('foo', [d.file('file.txt', 'foo')]),
      d.dir('test', [d.file('file.txt', 'test')]),
      d.dir('web', [d.file('file.txt', 'web')])
    ]).create();

    await pubGet();
  });

  test("builds only the given directories", () async {
    await runPub(
        args: ["build", "foo", "bar"],
        output: new RegExp(r'Built 2 files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('bar', [d.file('file.txt', 'bar')]),
        d.dir('foo', [d.file('file.txt', 'foo')]),
        d.nothing('test'),
        d.nothing('web')
      ])
    ]).validate();
  });

  test("serves only the given directories", () async {
    await pubServe(args: ["foo", "bar"]);

    await requestShouldSucceed("file.txt", "bar", root: "bar");
    await requestShouldSucceed("file.txt", "foo", root: "foo");
    expectNotServed("test");
    expectNotServed("web");

    await endPubServe();
  });
}
