// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  // Regression test for issue 23113
  test('runs a named Dart application in a dependency', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', pubspec: {
        'name': 'foo',
        'version': '1.0.0'
      }, contents: [
        d.dir('bin', [d.file('bar.dart', "main() => print('foobar');")])
      ]);
    });

    await d.dir(appPath, [
      d.appPubspec({'foo': null})
    ]).create();

    await pubGet(args: ['--precompile']);

    var pub = await pubRunV2(args: ['foo:bar']);
    expect(pub.stdout, emits('foobar'));
    await pub.shouldExit();

    await d.dir('foo', [
      d.libPubspec('foo', '2.0.0'),
      d.dir('bin', [d.file('bar.dart', "main() => print('different');")])
    ]).create();

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'path': '../foo'}
        }
      })
    ]).create();

    await pubGet();

    pub = await pubRunV2(args: ['foo:bar']);
    expect(pub.stdout, emits('different'));
    await pub.shouldExit();
  });
}
