// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('loads package imports in a dependency', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('lib', [d.file('foo.dart', "final value = 'foobar';")]),
      d.dir('bin', [
        d.file('bar.dart', '''
import "package:foo/foo.dart";

main() => print(value);
''')
      ])
    ]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': '../foo'}
      })
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ['foo:bar']);
    expect(pub.stdout, emits('foobar'));
    await pub.shouldExit();
  });
}
