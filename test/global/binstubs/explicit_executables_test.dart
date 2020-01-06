// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('only creates binstubs for the listed executables', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'one': 'script', 'two': 'script', 'three': 'script'}
      }),
      d.dir('bin', [d.file('script.dart', "main() => print('ok');")])
    ]).create();

    await runPub(args: [
      'global',
      'activate',
      '--source',
      'path',
      '../foo',
      '-x',
      'one',
      '--executable',
      'three'
    ], output: contains('Installed executables one and three.'));

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('one'), contains('pub global run foo:script')),
        d.nothing(binStubName('two')),
        d.file(binStubName('three'), contains('pub global run foo:script'))
      ])
    ]).validate();
  });
}
