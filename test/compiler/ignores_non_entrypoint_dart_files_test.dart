// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import '../serve/utils.dart';
import 'utils.dart';

main() {
  setUp(() {
    return d.dir(appPath, [
      d.appPubspec(),
      d.dir('web', [
        d.file('file1.dart', 'var main = () => print("hello");'),
        d.file('file2.dart', 'void main(arg1, arg2, arg3) => print("hello");'),
        d.file('file3.dart', 'class Foo { void main() => print("hello"); }'),
        d.file('file4.dart', 'var foo;')
      ])
    ]).create();
  });

  testWithCompiler("build ignores non-entrypoint Dart files", (compiler) async {
    await pubGet();
    await runPub(
        args: ["build", "--web-compiler=${compiler.name}"],
        output: new RegExp(r'Built [\d]+ files? to "build".'));

    await d.dir(appPath, [
      d.dir('build', [d.nothing('web')])
    ]).validate();
  });

  testWithCompiler("serve ignores non-entrypoint Dart files", (compiler) async {
    await pubGet();
    await pubServe(compiler: compiler);
    await requestShould404("file1.dart.js");
    await requestShould404("file2.dart.js");
    await requestShould404("file3.dart.js");
    await requestShould404("file4.dart.js");
    await endPubServe();
  });
}
