// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:path/path.dart' as p;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("errors if an executable's script can't be found", () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'missing': 'not_here', 'nope': null}
      })
    ]).create();

    var pub = await startPub(args: ['global', 'activate', '-spath', '../foo']);

    expect(
        pub.stderr,
        emits('Warning: Executable "missing" runs '
            '"${p.join('bin', 'not_here.dart')}", which was not found in foo.'));
    expect(
        pub.stderr,
        emits('Warning: Executable "nope" runs '
            '"${p.join('bin', 'nope.dart')}", which was not found in foo.'));
    await pub.shouldExit();
  });
}
