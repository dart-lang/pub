// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

main() {
  test("includes Dart files in debug mode", () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [
        d.file('file1.dart', 'var main = () => print("hello");'),
        d.file('file2.dart', 'void main(arg1, arg2, arg3) => print("hello");'),
        d.file('file3.dart', 'class Foo { void main() => print("hello"); }'),
        d.file('file4.dart', 'var foo;')
      ])
    ]).create();

    await pubGet();
    await runPub(
        args: ["build", "--mode", "debug"],
        output: new RegExp(r'Built \d+ files to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.dir('web', [
          d.nothing('file1.dart.js'),
          d.file('file1.dart', isNot(isEmpty)),
          d.nothing('file2.dart.js'),
          d.file('file2.dart', isNot(isEmpty)),
          d.nothing('file3.dart.js'),
          d.file('file3.dart', isNot(isEmpty)),
          d.nothing('file4.dart.js'),
          d.file('file4.dart', isNot(isEmpty))
        ])
      ])
    ]).validate();
  });
}
