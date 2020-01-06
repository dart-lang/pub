// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('runs a Dart application in the entrypoint package', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('tool', [
        d.file('app.dart', "main() => print('tool');"),
        d.dir('sub', [d.file('app.dart', "main() => print('sub');")])
      ])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: [path.join('tool', 'app')]);
    expect(pub.stdout, emits('tool'));
    await pub.shouldExit();

    pub = await pubRun(args: [path.join('tool', 'sub', 'app')]);
    expect(pub.stdout, emits('sub'));
    await pub.shouldExit();
  });
}
