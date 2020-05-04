// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('runs default Dart application without arguments', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('myapp.dart', "main() => print('foobar');")])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: []);
    expect(pub.stdout, emits('foobar'));
    await pub.shouldExit();
  });

  test('runs main.dart Dart application without arguments', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('main.dart', "main() => print('foobar');")])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: []);
    expect(pub.stdout, emits('foobar'));
    await pub.shouldExit();
  });

  test('prefers default Dart application without arguments', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [
        d.file('myapp.dart', "main() => print('foobar');"),
        d.file('main.dart', "main() => print('-');"),
      ])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: []);
    expect(pub.stdout, emits('foobar'));
    await pub.shouldExit();
  });
}
