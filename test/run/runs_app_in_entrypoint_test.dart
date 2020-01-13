// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const SCRIPT = """
import 'dart:io';

main() {
  stdout.writeln("stdout output");
  stderr.writeln("stderr output");
  exitCode = 123;
}
""";

void main() {
  test('runs a Dart application in the entrypoint package', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', SCRIPT)])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ['bin/script']);
    expect(pub.stdout, emits('stdout output'));
    expect(pub.stderr, emits('stderr output'));
    await pub.shouldExit(123);
  });
}
