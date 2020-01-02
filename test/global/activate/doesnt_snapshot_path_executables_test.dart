// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test("doesn't snapshots the executables for a path package", () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('hello.dart', "void main() => print('hello!');")])
    ]).create();

    await runPub(
        args: ['global', 'activate', '-spath', '../foo'],
        output: isNot(contains('Precompiled foo:hello.')));

    await d.dir(cachePath, [
      d.dir('global_packages', [
        d.dir('foo',
            [d.file('pubspec.lock', contains('1.0.0')), d.nothing('bin')])
      ])
    ]).validate();
  });
}
