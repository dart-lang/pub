// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pub/src/io.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activates a package at a local path', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    var path = canonicalize(p.join(d.sandbox, 'foo'));
    await runPub(
        args: ['global', 'activate', '--source', 'path', '../foo'],
        output: endsWith('Activated foo 1.0.0 at path "$path".'));
  });

  // Regression test for #1751
  test('activates a package at a local path with a relative path dependency',
      () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0', deps: {
        'bar': {'path': '../bar'}
      }),
      d.dir('bin', [
        d.file('foo.dart', """
        import 'package:bar/bar.dart';

        main() => print(value);
      """)
      ])
    ]).create();

    await d.dir('bar', [
      d.libPubspec('bar', '1.0.0'),
      d.dir('lib', [d.file('bar.dart', "final value = 'ok';")])
    ]).create();

    var path = canonicalize(p.join(d.sandbox, 'foo'));
    await runPub(
        args: ['global', 'activate', '--source', 'path', '../foo'],
        output: endsWith('Activated foo 1.0.0 at path "$path".'));

    await runPub(
        args: ['global', 'run', 'foo'],
        output: 'ok',
        workingDirectory: p.current);
  });
}
