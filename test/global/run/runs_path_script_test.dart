// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('runs a script in a path package', () async {
    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0'),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    final pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit();
  });

  // Regression test of https://github.com/dart-lang/pub/issues/4536
  test('respects existing lockfile', () async {
    final server = await servePackages();
    server.serve('dep', '1.0.0');

    await d.dir('foo', [
      d.libPubspec('foo', '1.0.0', deps: {'dep': '^1.0.0'}),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    await pubGet(workingDirectory: p.join(d.sandbox, 'foo'));
    await runPub(args: ['global', 'activate', '--source', 'path', '../foo']);

    server.serve('dep', '1.0.1');

    final pub = await pubRun(global: true, args: ['foo']);
    expect(pub.stdout, emitsThrough('ok'));
    await pub.shouldExit();
  });
}
