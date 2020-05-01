// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('the spawned application can read line-by-line from stdin', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('script.dart', """
          import 'dart:io';

          main() {
            print("started");
            var line1 = stdin.readLineSync();
            print("between");
            var line2 = stdin.readLineSync();
            print(line1);
            print(line2);
          }
        """)
      ])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: ['myapp:script']);

    await expectLater(pub.stdout, emits('started'));
    pub.stdin.writeln('first');
    await expectLater(pub.stdout, emits('between'));
    pub.stdin.writeln('second');
    expect(pub.stdout, emits('first'));
    expect(pub.stdout, emits('second'));
    await pub.shouldExit(0);
  });

  test('the spawned application can read streamed from stdin', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('script.dart', """
          import 'dart:io';

          main() {
            print("started");
            stdin.listen(stdout.add);
          }
        """)
      ])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: ['myapp:script']);

    await expectLater(pub.stdout, emits('started'));
    pub.stdin.writeln('first');
    await expectLater(pub.stdout, emits('first'));
    pub.stdin.writeln('second');
    await expectLater(pub.stdout, emits('second'));
    pub.stdin.writeln('third');
    await expectLater(pub.stdout, emits('third'));
    await pub.stdin.close();
    await pub.shouldExit(0);
  });
}
