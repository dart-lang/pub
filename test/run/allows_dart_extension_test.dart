// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _script = """
import 'dart:io';

main() {
  stdout.writeln("stdout output");
  stderr.writeln("stderr output");
  exitCode = 123;
}
""";

void main() {
  test('allows a ".dart" extension on the argument', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', _script)])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ['script.dart']);
    expect(pub.stdout, emitsThrough('stdout output'));
    expect(pub.stderr, emitsThrough('stderr output'));
    await pub.shouldExit(123);
  });
}
