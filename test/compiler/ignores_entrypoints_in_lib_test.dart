// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
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
      d.dir('lib', [
        d.file('file.dart', 'void main() => print("hello");'),
      ]),
      d.dir('web', [
        d.file('index.html', 'html'),
      ])
    ]).create();
  });

  testWithCompiler("build ignores Dart entrypoints in lib", (compiler) async {
    await pubGet();
    await runPub(
        args: ["build", "--all", "--web-compiler=${compiler.name}"],
        output: new RegExp(r'Built [\d]+ files? to "build".'));

    await d.dir(appPath, [
      d.dir('build', [
        d.nothing('lib'),
      ])
    ]).validate();
  });

  testWithCompiler("serve ignores Dart entrypoints in lib", (compiler) async {
    await pubGet();
    await pubServe();
    await requestShould404("packages/myapp/file.dart.js");
    await endPubServe();
  });
}
