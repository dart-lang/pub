// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as p;
import 'package:pub/src/exit_codes.dart' as exit_codes;

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('Errors if the script does not exist.', () async {
    await d.dir(appPath, [d.appPubspec()]).create();

    await pubGet();
    var pub = await pubRun(args: [p.join('bin', 'script')]);
    expect(
        pub.stderr, emits("Could not find ${p.join("bin", "script.dart")}."));
    await pub.shouldExit(exit_codes.NO_INPUT);
  });
}
