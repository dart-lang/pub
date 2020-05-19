// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('runs the script with assertions enabled', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', 'main() { assert(false); }')])
    ]).create();

    await pubGet();
    await runPub(
        args: ['run', '--enable-asserts', 'myapp:script'],
        error: contains('Failed assertion'),
        exitCode: 255);
  });
}
